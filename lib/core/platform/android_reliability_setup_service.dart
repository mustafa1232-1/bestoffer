import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:maslaki/l10n/app_localizations.dart';

import '../i18n/app_localizations_context.dart';
import '../storage/secure_storage.dart';

final androidReliabilitySetupProvider =
    Provider<AndroidReliabilitySetupService>(
      (ref) => AndroidReliabilitySetupService(store: SecureStore()),
    );

class AndroidReliabilitySetupService {
  AndroidReliabilitySetupService({required this.store});

  final SecureStore store;

  static const _firstRunDoneKey = 'android_reliability_setup_done_v1';

  bool _running = false;

  Future<void> maybeRunFirstLaunchSetup(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_running) return;

    final alreadyDone = await store.readBool(_firstRunDoneKey) ?? false;
    if (alreadyDone) return;

    _running = true;
    try {
      final packageName = (await PackageInfo.fromPlatform()).packageName;
      final device = await _loadDeviceProfile();
      var permissions = await _requestCriticalPermissions();

      if (!context.mounted) return;
      final completed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        backgroundColor: const Color(0xFF0B2A4C),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setState) {
              Future<void> refreshPermissions() async {
                permissions = await _requestCriticalPermissions();
                if (!sheetContext.mounted) return;
                setState(() {});
              }

              Future<void> openOemSettings() async {
                await _openOemSettings(
                  profile: device,
                  packageName: packageName,
                );
              }

              Future<void> openFullScreenCallSettings() async {
                await _openFullScreenCallSettings(packageName: packageName);
              }

              return _AndroidReliabilitySheet(
                profile: device,
                permissions: permissions,
                onRefreshPermissions: refreshPermissions,
                onOpenOemSettings: openOemSettings,
                onOpenFullScreenSettings: openFullScreenCallSettings,
              );
            },
          );
        },
      );

      if (completed == true) {
        await store.writeBool(_firstRunDoneKey, true);
      }
    } finally {
      _running = false;
    }
  }

  Future<_CriticalPermissionState> _requestCriticalPermissions() async {
    final notification = await _requestPermission(Permission.notification);
    final microphone = await _requestPermission(Permission.microphone);
    final location = await _requestPermission(Permission.locationWhenInUse);
    final battery = await _requestPermission(
      Permission.ignoreBatteryOptimizations,
    );
    final bluetoothGranted = await _resolveBluetoothPermissionGranted();

    return _CriticalPermissionState(
      notificationGranted: notification.isGranted,
      microphoneGranted: microphone.isGranted,
      locationGranted: location.isGranted,
      batteryOptimizationIgnored: battery.isGranted,
      bluetoothGranted: bluetoothGranted,
    );
  }

  Future<bool> _resolveBluetoothPermissionGranted() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 31) {
        return true;
      }
      final bluetooth = await _requestPermission(Permission.bluetoothConnect);
      return bluetooth.isGranted || bluetooth.isLimited;
    } catch (_) {
      return true;
    }
  }

  Future<PermissionStatus> _requestPermission(Permission permission) async {
    try {
      var status = await permission.status;
      if (status.isGranted || status.isLimited) return status;
      status = await permission.request();
      return status;
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  Future<_AndroidOemProfile> _loadDeviceProfile() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final manufacturer = (info.manufacturer).trim();
    final brand = (info.brand).trim();
    final model = (info.model).trim();
    final sdk = info.version.sdkInt;

    final key = _resolveVendorKey('$manufacturer $brand');
    final base = _profiles[key] ?? _profiles['generic']!;
    return base.copyWith(
      manufacturer: manufacturer,
      brand: brand,
      model: model,
      sdkInt: sdk,
    );
  }

  Future<void> _openOemSettings({
    required _AndroidOemProfile profile,
    required String packageName,
  }) async {
    final specs = <_IntentSpec>[
      ...profile.intentSpecs,
      ..._commonIntentSpecs(packageName: packageName),
    ];

    for (final spec in specs) {
      final launched = await _tryLaunchIntent(spec);
      if (launched) return;
    }
    await openAppSettings();
  }

  Future<void> _openFullScreenCallSettings({
    required String packageName,
  }) async {
    final specs = <_IntentSpec>[
      _IntentSpec(
        action: 'android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT',
        data: 'package:$packageName',
      ),
      _IntentSpec(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {'android.provider.extra.APP_PACKAGE': packageName},
      ),
      _IntentSpec(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
      ),
    ];
    for (final spec in specs) {
      final launched = await _tryLaunchIntent(spec);
      if (launched) return;
    }
    await openAppSettings();
  }

  Future<bool> _tryLaunchIntent(_IntentSpec spec) async {
    try {
      final intent = AndroidIntent(
        action: spec.action,
        package: spec.packageName,
        componentName: spec.componentName,
        data: spec.data,
        arguments: spec.arguments,
      );
      final canResolve = await intent.canResolveActivity();
      if (canResolve != true) return false;
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _resolveVendorKey(String raw) {
    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    for (final entry in _vendorAliases.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'generic';
  }

  List<_IntentSpec> _commonIntentSpecs({required String packageName}) {
    return <_IntentSpec>[
      _IntentSpec(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$packageName',
      ),
      const _IntentSpec(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      ),
      _IntentSpec(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {'android.provider.extra.APP_PACKAGE': packageName},
      ),
      _IntentSpec(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
      ),
      const _IntentSpec(action: 'android.settings.SETTINGS'),
    ];
  }
}

class _AndroidReliabilitySheet extends StatelessWidget {
  const _AndroidReliabilitySheet({
    required this.profile,
    required this.permissions,
    required this.onRefreshPermissions,
    required this.onOpenOemSettings,
    required this.onOpenFullScreenSettings,
  });

  final _AndroidOemProfile profile;
  final _CriticalPermissionState permissions;
  final Future<void> Function() onRefreshPermissions;
  final Future<void> Function() onOpenOemSettings;
  final Future<void> Function() onOpenFullScreenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final steps = isEnglish ? profile.stepsEn : profile.stepsAr;
    final vendorLabel = _vendorDisplayName(l10n, profile.vendorKey);
    final supportedNames = _supportedDisplayNames(
      l10n,
    ).join(isEnglish ? ', ' : '، ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.androidReliabilitySetupTitle,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.androidReliabilitySetupBody,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.84),
                  fontSize: 13.6,
                ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: l10n.androidReliabilityYourDevice,
                value:
                    '${profile.manufacturer} • ${profile.brand} • ${profile.model} (Android ${profile.sdkInt})',
              ),
              const SizedBox(height: 12),
              _PermissionCard(permissions: permissions),
              const SizedBox(height: 12),
              _InfoCard(
                title: l10n.androidReliabilityOemGuideTitle(vendorLabel),
                value: steps.join('\n'),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.androidReliabilityCoveredProfiles,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                supportedNames,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontSize: 12.8,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRefreshPermissions,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(
                        l10n.androidReliabilityRequestPermissionsAgain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenOemSettings,
                      icon: const Icon(Icons.settings_suggest_outlined),
                      label: Text(l10n.androidReliabilityOpenOemSettings),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenFullScreenSettings,
                      icon: const Icon(Icons.call_outlined),
                      label: Text(
                        l10n.androidReliabilityConfigureFullScreenCalls,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.commonDone),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.permissions});

  final _CriticalPermissionState permissions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.androidReliabilityPermissionStatus,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            label: l10n.androidReliabilityPermissionNotifications,
            granted: permissions.notificationGranted,
          ),
          _PermissionRow(
            label: l10n.androidReliabilityPermissionMicrophone,
            granted: permissions.microphoneGranted,
          ),
          _PermissionRow(
            label: l10n.androidReliabilityPermissionLocation,
            granted: permissions.locationGranted,
          ),
          _PermissionRow(
            label: l10n.androidReliabilityPermissionIgnoreBattery,
            granted: permissions.batteryOptimizationIgnored,
          ),
          _PermissionRow(
            label: l10n.androidReliabilityPermissionBluetoothCalls,
            granted: permissions.bluetoothGranted,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final color = granted ? const Color(0xFF73F0B6) : const Color(0xFFFFB86B);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.94)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CriticalPermissionState {
  const _CriticalPermissionState({
    required this.notificationGranted,
    required this.microphoneGranted,
    required this.locationGranted,
    required this.batteryOptimizationIgnored,
    required this.bluetoothGranted,
  });

  final bool notificationGranted;
  final bool microphoneGranted;
  final bool locationGranted;
  final bool batteryOptimizationIgnored;
  final bool bluetoothGranted;
}

class _IntentSpec {
  const _IntentSpec({
    this.action,
    this.packageName,
    this.componentName,
    this.data,
    this.arguments,
  });

  final String? action;
  final String? packageName;
  final String? componentName;
  final String? data;
  final Map<String, dynamic>? arguments;
}

class _AndroidOemProfile {
  const _AndroidOemProfile({
    required this.vendorKey,
    required this.vendorLabel,
    required this.stepsAr,
    required this.stepsEn,
    required this.intentSpecs,
    this.manufacturer = '',
    this.brand = '',
    this.model = '',
    this.sdkInt = 0,
  });

  final String vendorKey;
  final String vendorLabel;
  final List<String> stepsAr;
  final List<String> stepsEn;
  final List<_IntentSpec> intentSpecs;
  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;

  _AndroidOemProfile copyWith({
    String? manufacturer,
    String? brand,
    String? model,
    int? sdkInt,
  }) {
    return _AndroidOemProfile(
      vendorKey: vendorKey,
      vendorLabel: vendorLabel,
      stepsAr: stepsAr,
      stepsEn: stepsEn,
      intentSpecs: intentSpecs,
      manufacturer: manufacturer ?? this.manufacturer,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      sdkInt: sdkInt ?? this.sdkInt,
    );
  }
}

String _vendorDisplayName(AppLocalizations l10n, String vendorKey) {
  switch (vendorKey) {
    case 'samsung':
      return l10n.androidReliabilityVendorSamsung;
    case 'xiaomi':
      return l10n.androidReliabilityVendorXiaomi;
    case 'huawei':
      return l10n.androidReliabilityVendorHuawei;
    case 'oppo':
      return l10n.androidReliabilityVendorOppo;
    case 'oneplus':
      return l10n.androidReliabilityVendorOnePlus;
    case 'vivo':
      return l10n.androidReliabilityVendorVivo;
    case 'asus':
      return l10n.androidReliabilityVendorAsus;
    case 'motorola':
      return l10n.androidReliabilityVendorMotorola;
    case 'nokia':
      return l10n.androidReliabilityVendorNokia;
    case 'sony':
      return l10n.androidReliabilityVendorSony;
    case 'google':
      return l10n.androidReliabilityVendorGoogle;
    case 'meizu':
      return l10n.androidReliabilityVendorMeizu;
    case 'transsion':
      return l10n.androidReliabilityVendorTranssion;
    case 'nothing':
      return l10n.androidReliabilityVendorNothing;
    case 'zte':
      return l10n.androidReliabilityVendorZte;
    case 'lg':
      return l10n.androidReliabilityVendorLg;
    case 'wiko':
      return l10n.androidReliabilityVendorWiko;
    case 'blackview':
      return l10n.androidReliabilityVendorBlackview;
    case 'unihertz':
      return l10n.androidReliabilityVendorUnihertz;
    default:
      return l10n.androidReliabilityVendorGeneric;
  }
}

List<String> _supportedDisplayNames(AppLocalizations l10n) => [
  l10n.androidReliabilityVendorSamsung,
  l10n.androidReliabilityVendorXiaomi,
  l10n.androidReliabilityVendorHuawei,
  l10n.androidReliabilityVendorOppo,
  l10n.androidReliabilityVendorOnePlus,
  l10n.androidReliabilityVendorVivo,
  l10n.androidReliabilityVendorAsus,
  l10n.androidReliabilityVendorMotorola,
  l10n.androidReliabilityVendorNokia,
  l10n.androidReliabilityVendorSony,
  l10n.androidReliabilityVendorGoogle,
  l10n.androidReliabilityVendorMeizu,
  l10n.androidReliabilityVendorTranssion,
  l10n.androidReliabilityVendorNothing,
  l10n.androidReliabilityVendorZte,
  l10n.androidReliabilityVendorLg,
  l10n.androidReliabilityVendorWiko,
  l10n.androidReliabilityVendorBlackview,
  l10n.androidReliabilityVendorUnihertz,
];

const Map<String, String> _vendorAliases = {
  'samsung': 'samsung',
  'xiaomi': 'xiaomi',
  'redmi': 'xiaomi',
  'poco': 'xiaomi',
  'huawei': 'huawei',
  'honor': 'huawei',
  'oppo': 'oppo',
  'realme': 'oppo',
  'oneplus': 'oneplus',
  'vivo': 'vivo',
  'iqoo': 'vivo',
  'asus': 'asus',
  'motorola': 'motorola',
  'lenovo': 'motorola',
  'nokia': 'nokia',
  'hmd': 'nokia',
  'sony': 'sony',
  'google': 'google',
  'pixel': 'google',
  'meizu': 'meizu',
  'tecno': 'transsion',
  'infinix': 'transsion',
  'itel': 'transsion',
  'nothing': 'nothing',
  'zte': 'zte',
  'lg': 'lg',
  'wiko': 'wiko',
  'blackview': 'blackview',
  'unihertz': 'unihertz',
};

final Map<String, _AndroidOemProfile> _profiles = {
  'generic': const _AndroidOemProfile(
    vendorKey: 'generic',
    vendorLabel: 'Generic Android',
    stepsAr: [
      '1) فعّل الإشعارات (الصوت + المنبثقة + شاشة القفل).',
      '2) عطّل تحسين البطارية للتطبيق (Unrestricted / No restrictions).',
      '3) اسمح للتطبيق بالعمل بالخلفية وبالتشغيل التلقائي إن وجد.',
      '4) في أندرويد 14+ فعّل Full-screen notifications للمكالمات.',
    ],
    stepsEn: [
      '1) Enable notifications (sound + pop-up + lock screen).',
      '2) Disable battery optimization for this app (Unrestricted).',
      '3) Allow background run and auto-start if available.',
      '4) On Android 14+, allow full-screen call notifications.',
    ],
    intentSpecs: [],
  ),
  'samsung': const _AndroidOemProfile(
    vendorKey: 'samsung',
    vendorLabel: 'Samsung',
    stepsAr: [
      '1) Battery > Background usage limits > Never sleeping apps.',
      '2) فعّل إشعارات المكالمات والرسائل مع الصوت.',
      '3) اجعل البطارية للتطبيق Unrestricted.',
    ],
    stepsEn: [
      '1) Battery > Background usage limits > Never sleeping apps.',
      '2) Enable call/message notifications with sound.',
      '3) Set battery mode to Unrestricted for the app.',
    ],
    intentSpecs: [],
  ),
  'xiaomi': const _AndroidOemProfile(
    vendorKey: 'xiaomi',
    vendorLabel: 'Xiaomi / Redmi / POCO',
    stepsAr: [
      '1) Security > Autostart > فعّل التطبيق.',
      '2) Battery > App battery saver > No restrictions.',
      '3) فعّل الإشعارات المنبثقة والصوت وشاشة القفل.',
    ],
    stepsEn: [
      '1) Security > Autostart > enable this app.',
      '2) Battery > App battery saver > No restrictions.',
      '3) Enable pop-up + sound + lock-screen notifications.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.miui.securitycenter',
        componentName:
            'com.miui.permcenter.autostart.AutoStartManagementActivity',
      ),
      _IntentSpec(
        packageName: 'com.miui.securitycenter',
        componentName: 'com.miui.powercenter.PowerSettings',
      ),
    ],
  ),
  'huawei': const _AndroidOemProfile(
    vendorKey: 'huawei',
    vendorLabel: 'Huawei / Honor',
    stepsAr: [
      '1) App launch > إدارة يدوية > اسمح Auto-launch وBackground.',
      '2) Battery > Ignore optimizations للتطبيق.',
      '3) فعّل إشعارات المكالمات والرسائل كاملة.',
    ],
    stepsEn: [
      '1) App launch > manage manually > allow auto/background launch.',
      '2) Battery > ignore optimizations for this app.',
      '3) Fully enable call/message notifications.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.huawei.systemmanager',
        componentName:
            'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      ),
      _IntentSpec(
        packageName: 'com.huawei.systemmanager',
        componentName:
            'com.huawei.systemmanager.optimize.process.ProtectActivity',
      ),
    ],
  ),
  'oppo': const _AndroidOemProfile(
    vendorKey: 'oppo',
    vendorLabel: 'OPPO / realme',
    stepsAr: [
      '1) Auto launch > فعّل التطبيق.',
      '2) Battery > Allow background activity / No restrictions.',
      '3) فعّل الإشعارات العائمة وشاشة القفل.',
    ],
    stepsEn: [
      '1) Auto launch > enable this app.',
      '2) Battery > allow background activity / no restrictions.',
      '3) Enable floating + lock-screen notifications.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.coloros.safecenter',
        componentName:
            'com.coloros.safecenter.startupapp.StartupAppListActivity',
      ),
      _IntentSpec(
        packageName: 'com.oppo.safe',
        componentName:
            'com.oppo.safe.permission.startup.StartupAppListActivity',
      ),
    ],
  ),
  'oneplus': const _AndroidOemProfile(
    vendorKey: 'oneplus',
    vendorLabel: 'OnePlus',
    stepsAr: [
      '1) Battery optimization > Don’t optimize للتطبيق.',
      '2) Background app management > اسمح التشغيل بالخلفية.',
      '3) فعّل إشعارات المكالمات بصيغة Full-screen.',
    ],
    stepsEn: [
      '1) Battery optimization > Don’t optimize this app.',
      '2) Background app management > allow background run.',
      '3) Enable full-screen call notifications.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.oneplus.security',
        componentName:
            'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
      ),
    ],
  ),
  'vivo': const _AndroidOemProfile(
    vendorKey: 'vivo',
    vendorLabel: 'vivo / iQOO',
    stepsAr: [
      '1) iManager > Autostart manager > فعّل التطبيق.',
      '2) Battery > High background power consumption > Allow.',
      '3) فعّل الإشعارات الكاملة والصوت.',
    ],
    stepsEn: [
      '1) iManager > Autostart manager > enable this app.',
      '2) Battery > High background power consumption > Allow.',
      '3) Fully enable notifications and sounds.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.vivo.permissionmanager',
        componentName:
            'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
      ),
      _IntentSpec(
        packageName: 'com.iqoo.secure',
        componentName: 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity',
      ),
    ],
  ),
  'asus': const _AndroidOemProfile(
    vendorKey: 'asus',
    vendorLabel: 'ASUS',
    stepsAr: [
      '1) Auto-start manager > فعّل التطبيق.',
      '2) Battery optimization > Don’t optimize.',
      '3) فعّل إشعارات الشاشة الكاملة للمكالمات.',
    ],
    stepsEn: [
      '1) Auto-start manager > enable this app.',
      '2) Battery optimization > Don’t optimize.',
      '3) Enable full-screen call notifications.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.asus.mobilemanager',
        componentName: 'com.asus.mobilemanager.entry.FunctionActivity',
      ),
    ],
  ),
  'motorola': const _AndroidOemProfile(
    vendorKey: 'motorola',
    vendorLabel: 'Motorola / Lenovo',
    stepsAr: [
      '1) Battery > Background restrictions > None.',
      '2) فعّل الإشعارات الكاملة (Heads-up + lock screen).',
      '3) اسمح بالمايكروفون والموقع دائمًا أثناء الاستخدام.',
    ],
    stepsEn: [
      '1) Battery > Background restrictions > None.',
      '2) Enable full notifications (heads-up + lock screen).',
      '3) Allow microphone and location while in use.',
    ],
    intentSpecs: [],
  ),
  'nokia': const _AndroidOemProfile(
    vendorKey: 'nokia',
    vendorLabel: 'Nokia / HMD',
    stepsAr: [
      '1) Battery > Unrestricted للتطبيق.',
      '2) فعّل الإشعارات مع الصوت.',
      '3) ألغِ أي Data Saver أو Background restriction للتطبيق.',
    ],
    stepsEn: [
      '1) Set app battery mode to Unrestricted.',
      '2) Enable notifications with sound.',
      '3) Remove data saver/background restrictions for this app.',
    ],
    intentSpecs: [],
  ),
  'sony': const _AndroidOemProfile(
    vendorKey: 'sony',
    vendorLabel: 'Sony',
    stepsAr: [
      '1) Battery optimization > Don’t optimize.',
      '2) Stamina mode: استثنِ التطبيق.',
      '3) فعّل إشعارات المكالمات مع الظهور المنبثق.',
    ],
    stepsEn: [
      '1) Battery optimization > Don’t optimize.',
      '2) Exclude app from Stamina mode.',
      '3) Enable call notifications with pop-up.',
    ],
    intentSpecs: [],
  ),
  'google': const _AndroidOemProfile(
    vendorKey: 'google',
    vendorLabel: 'Google Pixel',
    stepsAr: [
      '1) Battery > App battery usage > Unrestricted.',
      '2) Notifications > Allow + sound + pop on screen.',
      '3) في Android 14+ فعّل Full-screen notifications للمكالمات.',
    ],
    stepsEn: [
      '1) Battery > App battery usage > Unrestricted.',
      '2) Notifications > allow + sound + pop on screen.',
      '3) On Android 14+, enable full-screen call notifications.',
    ],
    intentSpecs: [],
  ),
  'meizu': const _AndroidOemProfile(
    vendorKey: 'meizu',
    vendorLabel: 'Meizu',
    stepsAr: [
      '1) Security > Permissions > Auto-start.',
      '2) Battery > Smart background > allow app.',
      '3) فعّل الإشعارات والصوت.',
    ],
    stepsEn: [
      '1) Security > Permissions > Auto-start.',
      '2) Battery > Smart background > allow app.',
      '3) Enable notifications and sound.',
    ],
    intentSpecs: [
      _IntentSpec(
        packageName: 'com.meizu.safe',
        componentName: 'com.meizu.safe.permission.PermissionMainActivity',
      ),
    ],
  ),
  'transsion': const _AndroidOemProfile(
    vendorKey: 'transsion',
    vendorLabel: 'Transsion (Tecno/Infinix/itel)',
    stepsAr: [
      '1) Phone Master / Security > Auto-start > فعّل التطبيق.',
      '2) Battery > No restrictions.',
      '3) فعّل الإشعارات الكاملة وشاشة القفل.',
    ],
    stepsEn: [
      '1) Phone Master / Security > Auto-start > enable app.',
      '2) Battery > No restrictions.',
      '3) Enable full and lock-screen notifications.',
    ],
    intentSpecs: [],
  ),
  'nothing': const _AndroidOemProfile(
    vendorKey: 'nothing',
    vendorLabel: 'Nothing',
    stepsAr: [
      '1) Battery > Unrestricted.',
      '2) Notifications > Allow all + sound.',
      '3) فعّل صلاحيات المايك والموقع.',
    ],
    stepsEn: [
      '1) Battery > Unrestricted.',
      '2) Notifications > allow all + sound.',
      '3) Enable microphone and location permissions.',
    ],
    intentSpecs: [],
  ),
  'zte': const _AndroidOemProfile(
    vendorKey: 'zte',
    vendorLabel: 'ZTE',
    stepsAr: [
      '1) Auto-start / background protection > allow app.',
      '2) Battery optimization > Don’t optimize.',
      '3) Notifications > Full alerts.',
    ],
    stepsEn: [
      '1) Auto-start / background protection > allow app.',
      '2) Battery optimization > Don’t optimize.',
      '3) Notifications > full alerts.',
    ],
    intentSpecs: [],
  ),
  'lg': const _AndroidOemProfile(
    vendorKey: 'lg',
    vendorLabel: 'LG',
    stepsAr: [
      '1) Battery saver > exclude app.',
      '2) Background restrictions > none.',
      '3) فعّل الإشعارات مع الصوت.',
    ],
    stepsEn: [
      '1) Battery saver > exclude app.',
      '2) Background restrictions > none.',
      '3) Enable notifications with sound.',
    ],
    intentSpecs: [],
  ),
  'wiko': const _AndroidOemProfile(
    vendorKey: 'wiko',
    vendorLabel: 'Wiko',
    stepsAr: [
      '1) Power saving > allow background activity.',
      '2) Disable aggressive battery saving for app.',
      '3) Enable full notifications.',
    ],
    stepsEn: [
      '1) Power saving > allow background activity.',
      '2) Disable aggressive battery saving for app.',
      '3) Enable full notifications.',
    ],
    intentSpecs: [],
  ),
  'blackview': const _AndroidOemProfile(
    vendorKey: 'blackview',
    vendorLabel: 'Blackview',
    stepsAr: [
      '1) DuraSpeed/Battery manager > whitelist app.',
      '2) Allow autostart and background run.',
      '3) Enable lock-screen and pop-up notifications.',
    ],
    stepsEn: [
      '1) DuraSpeed/Battery manager > whitelist app.',
      '2) Allow autostart and background run.',
      '3) Enable lock-screen and pop-up notifications.',
    ],
    intentSpecs: [],
  ),
  'unihertz': const _AndroidOemProfile(
    vendorKey: 'unihertz',
    vendorLabel: 'Unihertz',
    stepsAr: [
      '1) Battery optimization > Don’t optimize.',
      '2) Allow background activity.',
      '3) Enable full call notifications.',
    ],
    stepsEn: [
      '1) Battery optimization > Don’t optimize.',
      '2) Allow background activity.',
      '3) Enable full call notifications.',
    ],
    intentSpecs: [],
  ),
};
