import 'package:flutter/services.dart';

import 'ar_effect_models.dart';
import 'ar_effect_provider.dart';

/// A platform-channel-backed AR provider. One implementation serves every native
/// SDK (DeepAR, Banuba, …) — only the channel name + license token differ.
///
/// The native side (Android Kotlin / iOS Swift) implements the method channel by
/// driving the real SDK and rendering into the camera surface. Until that native
/// code + license token exist, every call degrades gracefully:
/// `MissingPluginException` → reported as "not linked" (never a crash, never a
/// fake effect). The license token is injected at build time via --dart-define
/// (e.g. `--dart-define=MASLAKI_DEEPAR_LICENSE=xxxx`) so no secret is committed.
class ChannelArProvider implements ArEffectProvider {
  @override
  final String id;
  final MethodChannel _channel;
  final String _licenseKey;

  ChannelArProvider({
    required this.id,
    required String channelName,
    required String licenseKey,
  })  : _channel = MethodChannel(channelName),
        _licenseKey = licenseKey;

  bool get _hasLicense => _licenseKey.trim().isNotEmpty;

  @override
  Future<ArCapability> capability() async {
    if (!_hasLicense) {
      return ArCapability.unavailable(id, 'missing_license_token');
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('capability');
      if (raw == null) return ArCapability.unavailable(id, 'no_capability');
      return ArCapability(
        providerId: id,
        sdkLinked: raw['sdkLinked'] == true,
        licensed: raw['licensed'] == true,
        faceTracking: raw['faceTracking'] == true,
        backgroundSegmentation: raw['backgroundSegmentation'] == true,
        unavailableReason: raw['reason'] as String?,
      );
    } on MissingPluginException {
      return ArCapability.unavailable(id, 'native_sdk_not_linked');
    } on PlatformException catch (e) {
      return ArCapability.unavailable(id, e.code);
    }
  }

  @override
  Future<bool> initialize() async {
    if (!_hasLicense) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('initialize', {
        'licenseKey': _licenseKey,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<ArEffect>> availableEffects() async {
    if (!_hasLicense) return const <ArEffect>[];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('availableEffects');
      if (raw == null) return const <ArEffect>[];
      return raw
          .whereType<Map>()
          .map((item) => _effectFromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on MissingPluginException {
      return const <ArEffect>[];
    } on PlatformException {
      return const <ArEffect>[];
    }
  }

  @override
  Future<void> applyEffect(String? effectId) async {
    if (!_hasLicense) return;
    try {
      await _channel.invokeMethod<void>('applyEffect', {'effectId': effectId});
    } on MissingPluginException {
      // Native side absent — safe no-op.
    } on PlatformException {
      // Engine rejected the effect — safe no-op.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // nothing to release
    } on PlatformException {
      // best effort
    }
  }

  ArEffect _effectFromMap(Map<String, dynamic> map) {
    final categoryName = (map['category'] ?? 'funny').toString();
    final category = ArEffectCategory.values.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => ArEffectCategory.funny,
    );
    return ArEffect(
      id: (map['id'] ?? '').toString(),
      arabicName: (map['arabicName'] ?? map['name'] ?? '').toString(),
      englishName: (map['englishName'] ?? map['name'] ?? '').toString(),
      category: category,
      providerId: id,
      assetSlug: (map['assetSlug'] ?? map['slug'] ?? '').toString(),
      supported: map['supported'] == true,
    );
  }
}

/// DeepAR provider — channel `maslaki/ar/deepar`, license via
/// `--dart-define=MASLAKI_DEEPAR_LICENSE=...`.
ChannelArProvider buildDeepArProvider() => ChannelArProvider(
      id: 'deepar',
      channelName: 'maslaki/ar/deepar',
      licenseKey: const String.fromEnvironment('MASLAKI_DEEPAR_LICENSE'),
    );

/// Banuba provider — channel `maslaki/ar/banuba`, token via
/// `--dart-define=MASLAKI_BANUBA_TOKEN=...`.
ChannelArProvider buildBanubaProvider() => ChannelArProvider(
      id: 'banuba',
      channelName: 'maslaki/ar/banuba',
      licenseKey: const String.fromEnvironment('MASLAKI_BANUBA_TOKEN'),
    );
