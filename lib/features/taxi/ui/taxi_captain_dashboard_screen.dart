import 'dart:async';

import 'package:maslaki/features/taxi/data/taxi_route_service.dart';
import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';
import 'package:maslaki/features/taxi/domain/taxi_fare_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/session_invalidation.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import 'package:core_maps/core_maps.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/desktop_dashboard_frame.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import '../../tracking/tracking_map_utils.dart';
import '../data/taxi_api.dart';
import 'taxi_captain_loyalty_screen.dart';

final taxiCaptainApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio, realtime: ref.read(maslakiRealtimeServiceProvider));
});

final taxiCaptainRouteServiceProvider = Provider<TaxiRouteService>((ref) {
  return TaxiRouteService();
});

// ignore: unused_element
const Map<String, String> _taxiCaptainBrokenArabicFallbacks = {
  'Connected in real-time': 'متصل لحظيًا',
  'Status: Available': 'الحالة: متاح',
  'Status: Unavailable': 'الحالة: غير متاح',
  'Map follows you': 'الخريطة تتبعك',
  'Map in free mode': 'الخريطة في وضع حر',
  'Rides': 'الرحلات',
  'Dashboard': 'اللوحة',
  'Profile': 'الملف الشخصي',
  'Disable Tracking': 'إيقاف التتبع',
  'Enable Tracking': 'تفعيل التتبع',
  'Live Refresh': 'تحديث حي',
  'Logout': 'تسجيل الخروج',
  'Send ride offer': 'إرسال عرض الرحلة',
  'Customer current fare': 'أجرة الزبون الحالية',
  'Cancel': 'إلغاء',
  'Send Offer': 'إرسال العرض',
  'Invalid fare': 'أجرة غير صالحة',
  'Offer sent successfully': 'تم إرسال العرض بنجاح',
  'Ride Chat': 'دردشة الرحلة',
  'You': 'أنت',
  'Customer': 'الزبون',
  'System': 'النظام',
  'Send': 'إرسال',
  'Profile Edit Request': 'طلب تعديل الملف الشخصي',
  'Name': 'الاسم',
  'Phone': 'الهاتف',
  'Car Make': 'نوع السيارة',
  'Car Model': 'موديل السيارة',
  'Submit': 'إرسال',
  'No changes to submit': 'لا توجد تغييرات للإرسال',
  'Taxi Captain Interface': 'واجهة كابتن التكسي',
  'New trips': 'الرحلات الجديدة',
  'Current trips': 'الرحلات الحالية',
  'Completed trips': 'الرحلات المكتملة',
  'Earnings': 'الأرباح',
  'Reports': 'التقارير',
  'Notifications': 'الإشعارات',
  'Account settings': 'إعدادات الحساب',
  'Support': 'الدعم',
  'Taxi Captain': 'كابتن التكسي',
  'Map Tracking': 'تتبع الخريطة',
  'Free Mode': 'وضع حر',
  'Refresh': 'تحديث',
  'Track': 'تتبع',
  'Free': 'حر',
  'Live update': 'تحديث حي',
  'Reconnecting': 'جارٍ إعادة الاتصال',
  'Last sync': 'آخر مزامنة',
  'Available for requests': 'متاح للطلبات',
  'Ride': 'رحلة',
  'Status': 'الحالة',
  'To': 'إلى',
  'Fare': 'الأجرة',
  'Open customer location': 'فتح موقع الزبون',
  'Open dropoff point': 'فتح موقع الوصول',
  'Chat': 'دردشة',
  'Head to customer': 'التوجّه إلى الزبون',
  'Start ride': 'بدء الرحلة',
  'End ride': 'إنهاء الرحلة',
  'New': 'جديد',
  'Your turn now': 'دورك الآن',
  'Waiting turn': 'بانتظار الدور',
  'Request': 'الطلب',
  'Customer fare': 'أجرة الزبون',
  'Your offer': 'عرضك',
  'Edit My Offer': 'تعديل عرضي',
  'Today': 'اليوم',
  'Week': 'الأسبوع',
  'Month': 'الشهر',
  'Total': 'الإجمالي',
  'All': 'الكل',
  'Ride history': 'سجل الرحلات',
  'Block': 'البلوك',
  'Building': 'البناية',
  'Apartment': 'الشقة',
  'Model': 'الموديل',
  'Year': 'السنة',
  'Plate': 'اللوحة',
  'Subscription active': 'الاشتراك فعال',
  'Remaining': 'المتبقي',
  'days': 'يوم',
  'Required amount': 'المبلغ المطلوب',
  'Discount': 'الخصم',
  'Searching for captain': 'جارٍ البحث عن كابتن',
  'Captain assigned': 'تم تعيين الكابتن',
  'On the way to customer': 'في الطريق إلى الزبون',
  'Ride in progress': 'الرحلة قيد التنفيذ',
  'Completed': 'مكتملة',
  'Cancelled': 'ملغاة',
  'Expired': 'منتهية',
  'Unknown': 'غير معروف',
};

String _repairTaxiCaptainArabicLabel(String ar, String en) {
  final normalized = ar.trim();
  if (normalized.isEmpty) return en;

  final hasArabicLetters = RegExp(r'[\u0600-\u06FF]').hasMatch(normalized);
  if (!hasArabicLetters) return en;

  final hasCommonMojibake = normalized.runes.any(
    (codePoint) =>
        codePoint == 0x00D8 ||
        codePoint == 0x00D9 ||
        codePoint == 0x00D0 ||
        codePoint == 0x00C3,
  );
  if (hasCommonMojibake) return en;

  return ar;
}

/// الشريط الجانبي المكتبي للكابتن، ويعرض الحالة اللحظية وأزرار التنقل السريع.
class _DesktopCaptainSidebar extends StatelessWidget {
  final String captainName;
  final bool online;
  final bool streamConnected;
  final bool followMe;
  final bool locked;
  final int activeTab;
  final ValueChanged<int> onSelectTab;
  final Future<void> Function()? onRefresh;
  final VoidCallback onToggleFollow;
  final VoidCallback onLogout;

  const _DesktopCaptainSidebar({
    required this.captainName,
    required this.online,
    required this.streamConnected,
    required this.followMe,
    required this.locked,
    required this.activeTab,
    required this.onSelectTab,
    required this.onRefresh,
    required this.onToggleFollow,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    String t(String ar, String en) => context.localizedText(
      ar: _repairTaxiCaptainArabicLabel(ar, en),
      en: en,
    );
    final scheme = Theme.of(context).colorScheme;
    final statusText = locked
        ? t(
            'مقيد لحين تفعيل الاشتراك',
            'Restricted until subscription activation',
          )
        : streamConnected
        ? t('متصل لحظيًا', 'Connected in real-time')
        : t('بانتظار المزامنة المباشرة', 'Waiting for real-time sync');

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              captainName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              t('لوحة التحكم السريعة للكابتن', 'Captain quick control panel'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 16),
            _DesktopCaptainInfoCard(
              icon: online ? Icons.radio_button_checked : Icons.pause_circle,
              title: online
                  ? t('الحالة: متاح', 'Status: Available')
                  : t('الحالة: غير متاح', 'Status: Unavailable'),
              subtitle: statusText,
            ),
            const SizedBox(height: 10),
            _DesktopCaptainInfoCard(
              icon: followMe ? Icons.gps_fixed : Icons.gps_not_fixed,
              title: followMe
                  ? t('الخريطة تتبعك', 'Map follows you')
                  : t('الخريطة في وضع حر', 'Map in free mode'),
              subtitle: t(
                'يمكنك تبديل التتبع المباشر بضغطة واحدة',
                'You can toggle live tracking with one tap',
              ),
            ),
            const SizedBox(height: 18),
            DesktopQuickActionButton(
              icon: Icons.local_taxi,
              label: t('الرحلات', 'Rides'),
              selected: activeTab == 0,
              onPressed: () => onSelectTab(0),
            ),
            const SizedBox(height: 10),
            DesktopQuickActionButton(
              icon: Icons.insights,
              label: t('اللوحة', 'Dashboard'),
              selected: activeTab == 1,
              onPressed: () => onSelectTab(1),
            ),
            const SizedBox(height: 10),
            DesktopQuickActionButton(
              icon: Icons.person,
              label: t('الملف الشخصي', 'Profile'),
              selected: activeTab == 2,
              onPressed: () => onSelectTab(2),
            ),
            const SizedBox(height: 18),
            DesktopQuickActionButton(
              icon: followMe ? Icons.gps_fixed : Icons.gps_not_fixed,
              label: followMe
                  ? t('إيقاف التتبع', 'Disable Tracking')
                  : t('تفعيل التتبع', 'Enable Tracking'),
              selected: followMe,
              onPressed: onToggleFollow,
            ),
            const SizedBox(height: 10),
            DesktopQuickActionButton(
              icon: Icons.refresh,
              label: t('تحديث حي', 'Live Refresh'),
              onPressed: onRefresh == null ? null : () => onRefresh!.call(),
            ),
            const SizedBox(height: 10),
            DesktopQuickActionButton(
              icon: Icons.logout,
              label: t('تسجيل الخروج', 'Logout'),
              onPressed: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopCaptainInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DesktopCaptainInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum TaxiCaptainDashboardTab { rides, dashboard, profile }

enum TaxiCaptainDashboardIntent {
  defaultHome,
  newTrips,
  currentTrips,
  completedTrips,
  cancelledTrips,
  earnings,
  reports,
  profile,
  tripDetails,
}

/// الشاشة الرئيسية لتجربة كابتن التاكسي، وتشمل الخريطة، الرحلات، اللوحة،
/// والملف الشخصي ضمن shell واحد.
class TaxiCaptainDashboardScreen extends ConsumerStatefulWidget {
  const TaxiCaptainDashboardScreen({
    super.key,
    this.initialTab = TaxiCaptainDashboardTab.rides,
    this.initialIntent = TaxiCaptainDashboardIntent.defaultHome,
    this.initialRideId,
  });

  final TaxiCaptainDashboardTab initialTab;
  final TaxiCaptainDashboardIntent initialIntent;
  final int? initialRideId;

  @override
  ConsumerState<TaxiCaptainDashboardScreen> createState() =>
      _TaxiCaptainDashboardScreenState();
}

class _TaxiCaptainDashboardScreenState
    extends ConsumerState<TaxiCaptainDashboardScreen>
    with WidgetsBindingObserver {
  static const _center = LatLng(33.3128, 44.3615);

  final _mapController = MapController();
  late final TaxiApi _api;
  late final TaxiRouteService _routeService;
  Timer? _ticker;
  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _streamReconnectTimer;
  late final VoidCallback _sessionInvalidationListener;

  bool _loading = true;
  bool _sending = false;
  bool _online = true;
  bool _streamConnected = false;
  bool _followMe = true;
  bool _routeLoading = false;
  bool _lifecycleResumed = true;
  int _tab = 0;
  int _tickCounter = 0;
  int _streamReconnectAttempt = 0;
  int? _lastStreamEventId;
  String _period = 'day';
  String? _dashboardHistoryFilterStatus;
  int? _focusedRideId;
  Map<String, dynamic>? _focusedRideSnapshot;
  bool _focusedRideUnavailable = false;
  bool _initialIntentApplied = false;

  String? _error;
  DateTime? _lastSync;
  DateTime? _lastRouteAt;
  DateTime? _lastRealtimeRefreshAt;

  LatLng? _captainPoint;
  LatLng? _lastRouteFrom;
  LatLng? _lastRouteTo;
  List<LatLng> _routePoints = const [];
  Map<String, dynamic>? _currentRideEnvelope;
  List<Map<String, dynamic>> _nearby = const [];
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;
  String _t(String ar, String en) =>
      context.localizedText(ar: _repairTaxiCaptainArabicLabel(ar, en), en: en);

  void _setTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  String _intentTitle(TaxiCaptainDashboardIntent intent) {
    switch (intent) {
      case TaxiCaptainDashboardIntent.defaultHome:
        return _t('واجهة كابتن التكسي', 'Taxi Captain Interface');
      case TaxiCaptainDashboardIntent.newTrips:
        return _t('الرحلات الجديدة', 'New trips');
      case TaxiCaptainDashboardIntent.currentTrips:
        return _t('الرحلات الحالية', 'Current trips');
      case TaxiCaptainDashboardIntent.completedTrips:
        return _t('الرحلات المكتملة', 'Completed trips');
      case TaxiCaptainDashboardIntent.cancelledTrips:
        return _t('الرحلات الملغاة', 'Cancelled trips');
      case TaxiCaptainDashboardIntent.earnings:
        return _t('الأرباح', 'Earnings');
      case TaxiCaptainDashboardIntent.reports:
        return _t('التقارير', 'Reports');
      case TaxiCaptainDashboardIntent.profile:
        return _t('الملف الشخصي', 'Profile');
      case TaxiCaptainDashboardIntent.tripDetails:
        return _t('تفاصيل الرحلة', 'Trip details');
    }
  }

  String _intentSubtitle(TaxiCaptainDashboardIntent intent) {
    switch (intent) {
      case TaxiCaptainDashboardIntent.defaultHome:
        return _t(
          'إدارة الرحلات والمتابعة اللحظية',
          'Trips management and live tracking',
        );
      case TaxiCaptainDashboardIntent.newTrips:
        return _t(
          'طلبات جديدة بانتظار العرض أو الرفض.',
          'New requests waiting for offer or decline.',
        );
      case TaxiCaptainDashboardIntent.currentTrips:
        return _t(
          'رحلاتك النشطة وخط سير التنفيذ الحالي.',
          'Your active rides and current execution route.',
        );
      case TaxiCaptainDashboardIntent.completedTrips:
        return _t(
          'سجل الرحلات المكتملة ضمن الفترة المحددة.',
          'History of completed rides for the selected period.',
        );
      case TaxiCaptainDashboardIntent.cancelledTrips:
        return _t(
          'سجل الرحلات الملغاة وأسباب الإلغاء.',
          'History of cancelled rides and cancellation reasons.',
        );
      case TaxiCaptainDashboardIntent.earnings:
        return _t(
          'ملخص الأرباح اليومية والأسبوعية والشهرية.',
          'Daily, weekly, and monthly earnings summary.',
        );
      case TaxiCaptainDashboardIntent.reports:
        return _t(
          'تحليل الأداء وسجل الرحلات التفصيلي.',
          'Performance analytics and detailed ride history.',
        );
      case TaxiCaptainDashboardIntent.profile:
        return _t(
          'بيانات الحساب والمركبة وحالة الاشتراك.',
          'Account, vehicle details, and subscription status.',
        );
      case TaxiCaptainDashboardIntent.tripDetails:
        return _t(
          'فتح رحلة محددة مباشرة عبر معرف الرحلة.',
          'Open a specific ride directly by ride ID.',
        );
    }
  }

  String _pageTitle() {
    if (widget.initialIntent != TaxiCaptainDashboardIntent.defaultHome) {
      return _intentTitle(widget.initialIntent);
    }
    if (_tab == TaxiCaptainDashboardTab.rides.index) {
      return _intentTitle(TaxiCaptainDashboardIntent.currentTrips);
    }
    if (_tab == TaxiCaptainDashboardTab.dashboard.index) {
      return _intentTitle(TaxiCaptainDashboardIntent.reports);
    }
    return _intentTitle(TaxiCaptainDashboardIntent.profile);
  }

  String _pageSubtitle() {
    if (widget.initialIntent != TaxiCaptainDashboardIntent.defaultHome) {
      return _intentSubtitle(widget.initialIntent);
    }
    if (_tab == TaxiCaptainDashboardTab.rides.index) {
      return _intentSubtitle(TaxiCaptainDashboardIntent.currentTrips);
    }
    if (_tab == TaxiCaptainDashboardTab.dashboard.index) {
      return _intentSubtitle(TaxiCaptainDashboardIntent.reports);
    }
    return _intentSubtitle(TaxiCaptainDashboardIntent.profile);
  }

  Future<void> _replaceCaptainView(
    TaxiCaptainDashboardIntent intent, {
    int? rideId,
  }) async {
    final sameIntent = widget.initialIntent == intent;
    final sameRideId = (widget.initialRideId ?? 0) == (rideId ?? 0);
    if (sameIntent && sameRideId) {
      if (!mounted) return;
      setState(() => _applyIntentToState(intent));
      if (rideId != null && rideId > 0) {
        await _focusRideById(rideId, showUnavailableMessage: true);
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TaxiCaptainDashboardScreen(
          initialIntent: intent,
          initialRideId: rideId,
        ),
      ),
    );
  }

  Future<void> _switchDashboardPeriod(String period) async {
    final didChange = _period != period;
    if (_tab != 1 || didChange) {
      setState(() {
        _tab = 1;
        _period = period;
      });
    }
    if (didChange || _dashboard == null) {
      await _refreshMeta();
    }
  }

  void _applyIntentToState(TaxiCaptainDashboardIntent intent) {
    switch (intent) {
      case TaxiCaptainDashboardIntent.defaultHome:
        break;
      case TaxiCaptainDashboardIntent.newTrips:
      case TaxiCaptainDashboardIntent.currentTrips:
      case TaxiCaptainDashboardIntent.tripDetails:
        _tab = TaxiCaptainDashboardTab.rides.index;
        _dashboardHistoryFilterStatus = null;
        break;
      case TaxiCaptainDashboardIntent.completedTrips:
        _tab = TaxiCaptainDashboardTab.dashboard.index;
        _period = 'all';
        _dashboardHistoryFilterStatus = 'completed';
        break;
      case TaxiCaptainDashboardIntent.cancelledTrips:
        _tab = TaxiCaptainDashboardTab.dashboard.index;
        _period = 'all';
        _dashboardHistoryFilterStatus = 'cancelled';
        break;
      case TaxiCaptainDashboardIntent.earnings:
        _tab = TaxiCaptainDashboardTab.dashboard.index;
        _period = 'month';
        _dashboardHistoryFilterStatus = null;
        break;
      case TaxiCaptainDashboardIntent.reports:
        _tab = TaxiCaptainDashboardTab.dashboard.index;
        _period = 'all';
        _dashboardHistoryFilterStatus = null;
        break;
      case TaxiCaptainDashboardIntent.profile:
        _tab = TaxiCaptainDashboardTab.profile.index;
        _dashboardHistoryFilterStatus = null;
        break;
    }
  }

  void _applyIntentPreset() {
    _applyIntentToState(widget.initialIntent);
  }

  Future<void> _applyInitialIntent() async {
    if (_initialIntentApplied) return;
    _initialIntentApplied = true;
    final rideId = widget.initialRideId;
    final intent = widget.initialIntent;
    if (intent == TaxiCaptainDashboardIntent.tripDetails &&
        rideId != null &&
        rideId > 0) {
      await _focusRideById(rideId, showUnavailableMessage: true);
      return;
    }
    if (rideId != null && rideId > 0) {
      await _focusRideById(rideId, showUnavailableMessage: true);
    }
  }

  Future<void> _focusRideById(
    int rideId, {
    bool showUnavailableMessage = false,
  }) async {
    if (rideId <= 0) return;
    if (!mounted) return;
    setState(() {
      _tab = TaxiCaptainDashboardTab.rides.index;
      _focusedRideId = rideId;
      _focusedRideUnavailable = false;
    });

    final activeRideId = _asInt(_ride?['id']);
    if (activeRideId == rideId) {
      _moveMapToRide(_ride);
      setState(() => _focusedRideSnapshot = null);
      return;
    }

    final nearbyMatch = _nearby.where((item) => _asInt(item['id']) == rideId);
    if (nearbyMatch.isNotEmpty) {
      _moveMapToRide(nearbyMatch.first);
      setState(() => _focusedRideSnapshot = null);
      return;
    }

    try {
      final details = await _api.getRideDetails(rideId);
      final ride = details['ride'];
      if (ride is Map && mounted) {
        final parsedRide = Map<String, dynamic>.from(ride);
        _moveMapToRide(parsedRide);
        setState(() {
          _focusedRideSnapshot = parsedRide;
          _focusedRideUnavailable = false;
        });
        return;
      }
    } catch (_) {
      // Fallback below will re-check from fresh tick before showing not found.
    }

    await _tick(full: true);
    if (!mounted) return;
    final refreshedActiveRideId = _asInt(_ride?['id']);
    final refreshedNearbyFound = _nearby.any(
      (item) => _asInt(item['id']) == rideId,
    );
    if (refreshedActiveRideId == rideId || refreshedNearbyFound) {
      setState(() {
        _focusedRideSnapshot = null;
        _focusedRideUnavailable = false;
      });
      return;
    }

    setState(() {
      _focusedRideSnapshot = null;
      _focusedRideUnavailable = true;
    });
    if (showUnavailableMessage) {
      _snack(
        _t(
          'لم نتمكن من العثور على الرحلة المطلوبة حالياً. تم تحديث البيانات.',
          'Requested ride is not available right now. Data has been refreshed.',
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionInvalidationListener = _handleSessionInvalidation;
    SessionInvalidationBus.instance.addListener(_sessionInvalidationListener);
    _applyIntentPreset();
    if (widget.initialIntent == TaxiCaptainDashboardIntent.defaultHome) {
      _tab = widget.initialTab.index;
    }
    final incomingRideId = widget.initialRideId;
    if (incomingRideId != null && incomingRideId > 0) {
      _focusedRideId = incomingRideId;
    }
    _api = ref.read(taxiCaptainApiProvider);
    _routeService = ref.read(taxiCaptainRouteServiceProvider);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SessionInvalidationBus.instance.removeListener(
      _sessionInvalidationListener,
    );
    _ticker?.cancel();
    _streamSub?.cancel();
    _streamReconnectTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleResumed = state == AppLifecycleState.resumed;
    if (_lifecycleResumed) unawaited(_tick(full: true));
  }

  void _handleSessionInvalidation() {
    if (!mounted) return;
    _ticker?.cancel();
    _ticker = null;
    _streamSub?.cancel();
    _streamSub = null;
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    setState(() {
      _currentRideEnvelope = null;
      _dashboard = null;
      _profile = null;
      _subscription = null;
      _nearby = const [];
      _routePoints = const [];
      _captainPoint = null;
      _lastStreamEventId = null;
      _lastRealtimeRefreshAt = null;
      _streamConnected = false;
      _focusedRideSnapshot = null;
      _focusedRideUnavailable = false;
      _loading = false;
      _error = null;
    });
  }

  /// يحمل بيانات الكابتن، الرحلات الحالية، والـ meta اللازمة لبناء اللوحة.
  Future<void> _bootstrap() async {
    if (!mounted) return;
    await _refreshMeta();
    if (!mounted) return;
    await _tick(full: true);
    if (!mounted) return;
    await _applyInitialIntent();
    if (!mounted) return;
    _connectStream();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _tick();
      _tickCounter++;
      if (_tickCounter % 6 == 0) await _refreshMeta();
    });
  }

  /// ينعش البيانات الخفيفة التي تتغير كثيراً بدون إعادة بناء كل الصفحة.
  Future<void> _refreshMeta() async {
    try {
      final result = await Future.wait([
        _api.getCaptainDashboard(period: _period, limit: 80),
        _api.getCaptainProfile(),
        _api.getCaptainSubscription(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = result[0];
        _profile = result[1];
        _subscription = result[2];
        _error = null;
        _lastSync = DateTime.now();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = _err(e));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = _t(
          'تعذر تحديث بيانات الكابتن',
          'Failed to refresh captain profile.',
        ),
      );
    }
  }

  Future<void> _tick({bool full = false}) async {
    if (!mounted || !_lifecycleResumed) return;
    if (_locked && !full) {
      setState(() {
        _loading = false;
        _routePoints = const [];
      });
      return;
    }

    try {
      final pos = await _position();
      if (pos != null) _captainPoint = LatLng(pos.latitude, pos.longitude);

      if (_online && pos != null) {
        final p = await _api.upsertCaptainPresence(
          isOnline: true,
          latitude: pos.latitude,
          longitude: pos.longitude,
          headingDeg: _sanitizeHeading(pos.heading),
          speedKmh: _sanitizeSpeed(pos.speed),
          accuracyM: pos.accuracy,
          radiusM: 4000,
        );
        _nearby = _toMapList(p['nearbyRequests']);
      }

      _currentRideEnvelope = await _api.getCurrentRideForCaptain();
      final rideId = _asInt(_ride?['id']);
      final rideStatus = '${_ride?['status'] ?? ''}';
      if (rideId != null &&
          pos != null &&
          canPublishTaxiRideLocation(
            lifecycleResumed: _lifecycleResumed,
            permissionGranted: true,
            assigned: true,
            status: rideStatus,
          )) {
        await _api.updateRideLocation(
          rideId: rideId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          headingDeg: _sanitizeHeading(pos.heading),
          speedKmh: _sanitizeSpeed(pos.speed),
          accuracyM: pos.accuracy,
        );
      }

      final focusedRideId = _focusedRideId;
      if (focusedRideId != null && focusedRideId > 0) {
        final activeRideId = _asInt(_ride?['id']);
        final nearbyHasFocused = _nearby.any(
          (item) => _asInt(item['id']) == focusedRideId,
        );
        if (activeRideId == focusedRideId || nearbyHasFocused) {
          _focusedRideSnapshot = null;
          _focusedRideUnavailable = false;
        }
      }

      if (_followMe && _captainPoint != null) {
        _mapController.move(_captainPoint!, 16.0);
      }

      await _refreshRoutePolyline();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _lastSync = DateTime.now();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _err(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          'تعذر تحديث بيانات الرحلات',
          'Failed to refresh rides data',
        );
      });
    }
  }

  /// يحدث polyline المسار الحالي بين نقاط الرحلة لتتبعها على الخريطة.
  Future<void> _refreshRoutePolyline({bool force = false}) async {
    final target = _resolveCaptainRouteTarget();
    if (target == null) {
      if (_routePoints.isNotEmpty && mounted) {
        setState(() => _routePoints = const []);
      }
      return;
    }

    final from = target.$1;
    final to = target.$2;
    final now = DateTime.now();

    if (!force &&
        _lastRouteFrom != null &&
        _lastRouteTo != null &&
        _lastRouteAt != null) {
      final movedFrom = _routeService.distanceMeters(_lastRouteFrom!, from);
      final movedTo = _routeService.distanceMeters(_lastRouteTo!, to);
      final age = now.difference(_lastRouteAt!);
      if (movedFrom < 45 && movedTo < 30 && age < const Duration(seconds: 16)) {
        return;
      }
    }

    if (!force && _routeLoading) return;

    if (mounted) {
      setState(() => _routeLoading = true);
    } else {
      _routeLoading = true;
    }

    try {
      final points = await _routeService.fetchDrivingRoute(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _lastRouteFrom = from;
        _lastRouteTo = to;
        _lastRouteAt = now;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = [from, to];
        _lastRouteFrom = from;
        _lastRouteTo = to;
        _lastRouteAt = now;
      });
    } finally {
      if (mounted) {
        setState(() => _routeLoading = false);
      } else {
        _routeLoading = false;
      }
    }
  }

  (LatLng, LatLng)? _resolveCaptainRouteTarget() {
    final ride = _ride ?? _focusedRideSnapshot;
    if (ride == null || _captainPoint == null) return null;

    final status = _str(ride['status']);
    final pickup = _latLng(ride['pickup']);
    final dropoff = _latLng(ride['dropoff']);

    if ((status == 'captain_assigned' || status == 'captain_arriving') &&
        pickup != null) {
      return (_captainPoint!, pickup);
    }
    if (status == 'ride_started' && dropoff != null) {
      return (_captainPoint!, dropoff);
    }
    if (_ride == null && pickup != null && dropoff != null) {
      return (pickup, dropoff);
    }
    return null;
  }

  void _moveMapToRide(Map<String, dynamic>? ride) {
    if (ride == null) return;
    final pickup = _latLng(ride['pickup']);
    final dropoff = _latLng(ride['dropoff']);
    final target = pickup ?? dropoff;
    if (target == null) return;
    try {
      _mapController.move(target, 16.2);
    } catch (_) {
      // Ignore map controller transient errors while first frame is mounting.
    }
  }

  Future<void> _openInWaze({
    required LatLng destination,
    required String targetLabel,
  }) async {
    try {
      await _routeService.openWazeNavigation(destination);
    } catch (_) {
      _snack(
        _t(
          'تعذر فتح تطبيق الخرائط لـ $targetLabel',
          'Unable to open maps app for $targetLabel',
        ),
      );
    }
  }

  void _connectStream() {
    _streamSub?.cancel();
    _streamReconnectTimer?.cancel();
    _streamSub = _api
        .streamEvents(lastEventId: _lastStreamEventId)
        .listen(
          (event) {
            if (!mounted) return;

            if (event.event == 'connected' || event.event == 'replayed') {
              _streamReconnectAttempt = 0;
              setState(() {
                _streamConnected = true;
                _lastSync = DateTime.now();
              });
              unawaited(_tick(full: true));
              unawaited(_refreshMeta());
              return;
            }

            if (event.event == 'resync_required') {
              _lastStreamEventId = _asInt(event.data['latestEventId']);
              setState(() {
                _streamConnected = true;
                _lastSync = DateTime.now();
              });
              _refreshFromRealtime(force: true);
              return;
            }

            if (event.event == 'heartbeat') {
              setState(() {
                _streamConnected = true;
                _lastSync = DateTime.now();
              });
              return;
            }

            if (!_acceptStreamEventId(event.eventId)) return;

            if (event.event == 'taxi_location_update') {
              _applyRealtimeLocation(event.data);
              return;
            }

            if (event.event.startsWith('taxi_') &&
                event.event != 'taxi_location_update') {
              _refreshFromRealtime();
              return;
            }

            _refreshFromRealtime();
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _streamConnected = false);
            _scheduleStreamReconnect();
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _streamConnected = false);
            _scheduleStreamReconnect();
          },
        );
  }

  bool _acceptStreamEventId(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    if (_lastStreamEventId != null && eventId <= _lastStreamEventId!) {
      return false;
    }
    _lastStreamEventId = eventId;
    return true;
  }

  void _refreshFromRealtime({bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastRealtimeRefreshAt != null) {
      final elapsed = now.difference(_lastRealtimeRefreshAt!);
      if (elapsed < const Duration(milliseconds: 900)) {
        return;
      }
    }
    _lastRealtimeRefreshAt = now;
    unawaited(_tick(full: true));
    unawaited(_refreshMeta());
  }

  void _applyRealtimeLocation(Map<String, dynamic> data) {
    final rideId = _asInt(data['rideId']);
    final activeRideId = _asInt(_ride?['id']);
    if (activeRideId != null && rideId != null && activeRideId != rideId) {
      return;
    }

    final location = data['location'] is Map
        ? Map<String, dynamic>.from(data['location'] as Map)
        : null;
    final point = _latLng(location);
    if (point == null || !mounted) return;

    setState(() {
      _streamConnected = true;
      _lastSync = DateTime.now();
      _captainPoint = point;
      if (_currentRideEnvelope != null && location != null) {
        _currentRideEnvelope = {
          ..._currentRideEnvelope!,
          'latestLocation': location,
        };
      }
    });
    unawaited(_refreshRoutePolyline());
  }

  void _scheduleStreamReconnect() {
    if (!mounted) return;
    if (_streamReconnectTimer?.isActive == true) return;

    _streamReconnectAttempt = (_streamReconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = switch (_streamReconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      5 => 20,
      _ => 30,
    };

    _streamReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _connectStream();
    });
  }

  Future<Position?> _position() async {
    if (!_lifecycleResumed) return null;
    final status = await ref
        .read(locationPermissionServiceProvider)
        .getStatus();
    if (!status.serviceEnabled) return null;
    final requested = await ref
        .read(locationPermissionServiceProvider)
        .requestPermission();
    if (!requested.isGranted) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
  }

  Future<void> _setOnline(bool value) async {
    setState(() => _online = value);
    if (!value) {
      final p = _captainPoint ?? _center;
      setState(() => _routePoints = const []);
      await _api.upsertCaptainPresence(
        isOnline: false,
        latitude: p.latitude,
        longitude: p.longitude,
        radiusM: 4000,
      );
    } else {
      await _tick(full: true);
    }
  }

  Future<void> _advance(String action) async {
    if (_locked) {
      _snack(
        _t(
          'الاشتراك منتهي. اطلب تسديد الاشتراك.',
          'Subscription expired. Request payment first.',
        ),
      );
      return;
    }
    final rideId = _asInt(_ride?['id']);
    if (rideId == null) return;
    setState(() => _sending = true);
    try {
      if (action == 'arrive') await _api.markArrived(rideId);
      if (action == 'start') await _api.startRide(rideId);
      if (action == 'complete') await _api.completeRide(rideId);
      await _tick(full: true);
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _requestCashPayment() async {
    setState(() => _sending = true);
    try {
      await _api.requestCaptainCashPayment();
      await _refreshMeta();
      _snack(
        _t('تم إرسال طلب التسديد للإدارة', 'Payment request sent to admin'),
      );
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitBid(Map<String, dynamic> ride) async {
    if (_locked) {
      _snack(
        _t(
          'الاشتراك منتهي. اطلب التسديد أولًا.',
          'Subscription expired. Request payment first.',
        ),
      );
      return;
    }
    final rideId = _asInt(ride['id']);
    if (rideId == null) return;

    final l10n = context.l10n;
    final nonAvailable = _t('غير متوفر', 'Not available');
    final baseFare = _asInt(ride['proposedFareIqd']);
    final fareCtrl = TextEditingController(
      text: baseFare != null && baseFare > 0 ? '$baseFare' : '',
    );
    final etaCtrl = TextEditingController(text: '8');
    final noteCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();

    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final fieldErrors = <String, String>{};
          String? formError;
          var submitting = false;

          Future<void> submit(StateSetter setModalState) async {
            if (submitting) return;

            final fare = tryParseLocalizedInt(fareCtrl.text.trim());
            final etaText = etaCtrl.text.trim();
            final eta = etaText.isEmpty ? null : tryParseLocalizedInt(etaText);
            final nextErrors = <String, String>{};

            if (fare == null || fare <= 0) {
              nextErrors['offeredFareIqd'] = resolveFormFieldError(
                l10n: l10n,
                field: 'offeredFareIqd',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.mapPageSuggestedFareLabel,
              );
            }
            if (etaText.isNotEmpty && (eta == null || eta < 1 || eta > 180)) {
              nextErrors['etaMinutes'] = resolveFormFieldError(
                l10n: l10n,
                field: 'etaMinutes',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.taxiCaptainOfferEtaLabel,
              );
            }

            if (nextErrors.isNotEmpty) {
              setModalState(() {
                fieldErrors
                  ..clear()
                  ..addAll(nextErrors);
                formError = l10n.validationReviewRequiredFields;
              });
              await scrollCoordinator.focusFirstError(const [
                'offeredFareIqd',
                'etaMinutes',
              ]);
              return;
            }

            setModalState(() {
              submitting = true;
              fieldErrors.clear();
              formError = null;
            });

            try {
              await _api.createBid(
                rideId: rideId,
                offeredFareIqd: fare!,
                etaMinutes: eta,
                note: noteCtrl.text.trim(),
              );
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext, true);
            } on DioException catch (e) {
              final parsed = parseBackendFieldErrors(e);
              final backendErrors = <String, String>{};
              if (parsed.hasAnyErrors) {
                for (final entry in parsed.fieldCodes.entries) {
                  if (entry.key == '_form') continue;
                  final fieldLabel = switch (entry.key) {
                    'offeredFareIqd' => l10n.mapPageSuggestedFareLabel,
                    'etaMinutes' => l10n.taxiCaptainOfferEtaLabel,
                    'note' => l10n.mapPageOptionalNote,
                    _ => null,
                  };
                  backendErrors[entry.key] = resolveFormFieldError(
                    l10n: l10n,
                    field: entry.key,
                    code: entry.value,
                    fieldLabel: fieldLabel,
                  );
                }
              }
              setModalState(() {
                submitting = false;
                if (backendErrors.isNotEmpty) {
                  fieldErrors
                    ..clear()
                    ..addAll(backendErrors);
                  formError = resolveFormLevelError(
                    l10n,
                    code: parsed.formCode,
                    fallback: l10n.validationReviewRequiredFields,
                  );
                } else {
                  formError = _err(e);
                }
              });
              if (backendErrors.isNotEmpty) {
                await scrollCoordinator.focusFirstError(const [
                  'offeredFareIqd',
                  'etaMinutes',
                  'note',
                ]);
              }
            } catch (_) {
              setModalState(() {
                submitting = false;
                formError = l10n.errorsServerFailure;
              });
            }
          }

          void applyQuickFare(StateSetter setModalState, int value) {
            fareCtrl.text = value.toString();
            setModalState(() {
              fieldErrors.remove('offeredFareIqd');
              formError = null;
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.84,
            minChildSize: 0.58,
            maxChildSize: 0.98,
            builder: (context, scrollController) {
              return StatefulBuilder(
                builder: (context, setModalState) {
                  final currentFare =
                      tryParseLocalizedInt(fareCtrl.text.trim()) ??
                      baseFare ??
                      0;
                  final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
                  return Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: Row(
                              children: [
                                const Icon(Icons.local_offer_rounded),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.taxiCaptainOfferDialogTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Directionality(
                                textDirection: context.appTextDirection,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FormErrorBanner(message: formError),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        '${l10n.taxiCaptainCurrentFareLabel}: ${baseFare != null && baseFare > 0 ? _money(baseFare) : nonAvailable}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _quickFareChip(
                                          label: _t('نفس السعر', 'Same price'),
                                          onPressed:
                                              baseFare == null || baseFare <= 0
                                              ? null
                                              : () => applyQuickFare(
                                                  setModalState,
                                                  baseFare,
                                                ),
                                        ),
                                        _quickFareChip(
                                          label: '+500',
                                          onPressed: () => applyQuickFare(
                                            setModalState,
                                            (currentFare + 500)
                                                .clamp(1, 5000000)
                                                .toInt(),
                                          ),
                                        ),
                                        _quickFareChip(
                                          label: '+1000',
                                          onPressed: () => applyQuickFare(
                                            setModalState,
                                            (currentFare + 1000)
                                                .clamp(1, 5000000)
                                                .toInt(),
                                          ),
                                        ),
                                        _quickFareChip(
                                          label: '+2000',
                                          onPressed: () => applyQuickFare(
                                            setModalState,
                                            (currentFare + 2000)
                                                .clamp(1, 5000000)
                                                .toInt(),
                                          ),
                                        ),
                                        _quickFareChip(
                                          label: _t('مخصص', 'Custom'),
                                          onPressed: () => scrollCoordinator
                                              .focusNodeFor('offeredFareIqd')
                                              .requestFocus(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    scrollCoordinator.anchor(
                                      'offeredFareIqd',
                                      TextField(
                                        controller: fareCtrl,
                                        focusNode: scrollCoordinator
                                            .focusNodeFor('offeredFareIqd'),
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (_) {
                                          if (fieldErrors.containsKey(
                                                'offeredFareIqd',
                                              ) ||
                                              formError != null) {
                                            setModalState(() {
                                              fieldErrors.remove(
                                                'offeredFareIqd',
                                              );
                                              if (fieldErrors.isEmpty) {
                                                formError = null;
                                              }
                                            });
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText:
                                              l10n.mapPageSuggestedFareLabel,
                                          prefixIcon: const Icon(
                                            Icons.price_change_rounded,
                                          ),
                                          errorText:
                                              fieldErrors['offeredFareIqd'],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    scrollCoordinator.anchor(
                                      'etaMinutes',
                                      TextField(
                                        controller: etaCtrl,
                                        focusNode: scrollCoordinator
                                            .focusNodeFor('etaMinutes'),
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (_) {
                                          if (fieldErrors.containsKey(
                                                'etaMinutes',
                                              ) ||
                                              formError != null) {
                                            setModalState(() {
                                              fieldErrors.remove('etaMinutes');
                                              if (fieldErrors.isEmpty) {
                                                formError = null;
                                              }
                                            });
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText:
                                              l10n.taxiCaptainOfferEtaLabel,
                                          prefixIcon: const Icon(
                                            Icons.timer_outlined,
                                          ),
                                          errorText: fieldErrors['etaMinutes'],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    scrollCoordinator.anchor(
                                      'note',
                                      TextField(
                                        controller: noteCtrl,
                                        focusNode: scrollCoordinator
                                            .focusNodeFor('note'),
                                        textInputAction: TextInputAction.done,
                                        maxLines: 3,
                                        onChanged: (_) {
                                          if (fieldErrors.containsKey('note') ||
                                              formError != null) {
                                            setModalState(() {
                                              fieldErrors.remove('note');
                                              if (fieldErrors.isEmpty) {
                                                formError = null;
                                              }
                                            });
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText: l10n.mapPageOptionalNote,
                                          prefixIcon: const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                          ),
                                          helperText: _t(
                                            'أنا قريب منك، أصل خلال 4 دقائق',
                                            'I am close, arriving in 4 minutes',
                                          ),
                                          errorText: fieldErrors['note'],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: submitting
                                          ? null
                                          : () => Navigator.pop(context, false),
                                      child: Text(l10n.commonCancel),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: submitting
                                          ? null
                                          : () => submit(setModalState),
                                      icon: submitting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.send_rounded),
                                      label: Text(
                                        submitting
                                            ? _t('جارٍ الإرسال', 'Sending')
                                            : l10n.commonSend,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );

      if (ok == true) {
        _snack(l10n.taxiCaptainOfferSent);
        await _tick(full: true);
      }
    } finally {
      scrollCoordinator.dispose();
      fareCtrl.dispose();
      etaCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _declineRideRequest(Map<String, dynamic> ride) async {
    if (_locked) {
      _snack(
        _t(
          'الاشتراك منتهي. اطلب التسديد أولًا.',
          'Subscription expired. Request payment first.',
        ),
      );
      return;
    }

    final rideId = _asInt(ride['id']);
    if (rideId == null || _sending) return;

    setState(() => _sending = true);
    try {
      await _api.declineRideRequest(rideId: rideId);
      _snack(
        _t(
          'تم رفض الطلب ولن يظهر لك مرة أخرى.',
          'Request declined and hidden from your queue.',
        ),
      );
      await _tick(full: true);
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _acceptCustomerFare(Map<String, dynamic> ride) async {
    if (_locked) {
      _snack(
        _t(
          'الاشتراك منتهي. اطلب التسديد أولًا.',
          'Subscription expired. Request payment first.',
        ),
      );
      return;
    }

    final rideId = _asInt(ride['id']);
    final proposedFare = _asInt(ride['proposedFareIqd']);
    if (rideId == null ||
        proposedFare == null ||
        proposedFare <= 0 ||
        _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      await _api.acceptCustomerFare(rideId: rideId);
      _snack(
        _t(
          'تم قبول السعر. الرحلة الآن نشطة بانتظار التحرك.',
          'Customer fare accepted. The ride is now active.',
        ),
      );
      await _tick(full: true);
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _quickFareChip({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.flash_on_rounded, size: 18),
      onPressed: onPressed,
    );
  }

  Future<void> _openRideChatBottomSheet(int rideId) async {
    final l10n = context.l10n;
    final textCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    List<Map<String, dynamic>> messages = const [];
    bool sending = false;
    String? localError;
    String? composerError;

    Future<void> refresh(StateSetter setModalState) async {
      try {
        final items = await _api.listRideChat(rideId: rideId, limit: 120);
        setModalState(() {
          messages = items;
          localError = null;
        });
      } on DioException catch (e) {
        setModalState(() => localError = _err(e));
      } catch (_) {
        setModalState(
          () => localError = _t('تعذر تحميل المحادثة', 'Failed to load chat'),
        );
      }
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (messages.isEmpty && localError == null) {
              unawaited(refresh(setModalState));
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
                top: 6,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.mapPageRideChatTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: localError != null
                            ? Center(
                                child: Text(
                                  localError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              )
                            : messages.isEmpty
                            ? Center(child: Text(l10n.mapPageRideChatEmpty))
                            : ListView.builder(
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final msg = messages[i];
                                  final role =
                                      _str(msg['senderRole']) ?? 'system';
                                  final senderName =
                                      _str(msg['sender']?['fullName']) ??
                                      (role == 'captain'
                                          ? l10n.commonYou
                                          : role == 'customer'
                                          ? l10n.commonCustomer
                                          : l10n.commonSystem);
                                  final text = _str(msg['messageText']) ?? '-';
                                  final mine = role == 'captain';
                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.green.withValues(
                                                alpha: 0.14,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            senderName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(text),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (composerError != null &&
                          composerError!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FormErrorBanner(message: composerError),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: scrollCoordinator.anchor(
                              'messageText',
                              TextField(
                                controller: textCtrl,
                                focusNode: scrollCoordinator.focusNodeFor(
                                  'messageText',
                                ),
                                textInputAction: TextInputAction.send,
                                onChanged: (_) {
                                  if (composerError == null &&
                                      localError == null) {
                                    return;
                                  }
                                  setModalState(() {
                                    composerError = null;
                                    localError = null;
                                  });
                                },
                                onSubmitted: (_) async {
                                  final text = textCtrl.text.trim();
                                  if (sending) return;
                                  if (text.isEmpty) {
                                    setModalState(
                                      () => composerError =
                                          l10n.validationMessageRequired,
                                    );
                                    await scrollCoordinator.focusFirstError(
                                      const ['messageText'],
                                    );
                                    return;
                                  }
                                  setModalState(() => sending = true);
                                  try {
                                    await _api.sendRideChatMessage(
                                      rideId: rideId,
                                      messageText: text,
                                    );
                                    textCtrl.clear();
                                    setModalState(() => composerError = null);
                                    await refresh(setModalState);
                                  } finally {
                                    setModalState(() => sending = false);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: l10n.mapPageWriteMessageHint,
                                  errorText: composerError,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: sending
                                ? null
                                : () async {
                                    final text = textCtrl.text.trim();
                                    if (text.isEmpty) {
                                      setModalState(
                                        () => composerError =
                                            l10n.validationMessageRequired,
                                      );
                                      await scrollCoordinator.focusFirstError(
                                        const ['messageText'],
                                      );
                                      return;
                                    }
                                    setModalState(() => sending = true);
                                    try {
                                      await _api.sendRideChatMessage(
                                        rideId: rideId,
                                        messageText: text,
                                      );
                                      textCtrl.clear();
                                      setModalState(() => composerError = null);
                                      await refresh(setModalState);
                                    } catch (_) {
                                      setModalState(() {
                                        localError =
                                            l10n.mapPageRideChatSendFailed;
                                      });
                                    } finally {
                                      setModalState(() => sending = false);
                                    }
                                  },
                            child: Text(l10n.commonSend),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    scrollCoordinator.dispose();
    textCtrl.dispose();
  }

  Future<void> _requestProfileEdit() async {
    final p = _profileMap;
    if (p == null) return;

    final l10n = context.l10n;
    final nameCtrl = TextEditingController(text: _str(p['fullName']) ?? '');
    final phoneCtrl = TextEditingController(text: _str(p['phone']) ?? '');
    final carMakeCtrl = TextEditingController(text: _str(p['carMake']) ?? '');
    final carModelCtrl = TextEditingController(text: _str(p['carModel']) ?? '');
    final noteCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final fieldErrors = <String, String>{};
          String? formError;
          var submitting = false;

          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submit() async {
                final changes = <String, dynamic>{};
                if (nameCtrl.text.trim().isNotEmpty &&
                    nameCtrl.text.trim() != (_str(p['fullName']) ?? '')) {
                  changes['fullName'] = nameCtrl.text.trim();
                }
                if (phoneCtrl.text.trim().isNotEmpty &&
                    phoneCtrl.text.trim() != (_str(p['phone']) ?? '')) {
                  changes['phone'] = phoneCtrl.text.trim();
                }
                if (carMakeCtrl.text.trim().isNotEmpty &&
                    carMakeCtrl.text.trim() != (_str(p['carMake']) ?? '')) {
                  changes['carMake'] = carMakeCtrl.text.trim();
                }
                if (carModelCtrl.text.trim().isNotEmpty &&
                    carModelCtrl.text.trim() != (_str(p['carModel']) ?? '')) {
                  changes['carModel'] = carModelCtrl.text.trim();
                }

                if (changes.isEmpty) {
                  setDialogState(() {
                    formError = l10n.taxiCaptainProfileEditNoChanges;
                  });
                  return;
                }

                setDialogState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });

                try {
                  await _api.requestCaptainProfileEdit(
                    requestedChanges: changes,
                    captainNote: noteCtrl.text.trim(),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                } on DioException catch (e) {
                  final parsed = parseBackendFieldErrors(e);
                  final backendErrors = <String, String>{};
                  if (parsed.hasAnyErrors) {
                    for (final entry in parsed.fieldCodes.entries) {
                      if (entry.key == '_form') continue;
                      final fieldLabel = switch (entry.key) {
                        'fullName' => l10n.commonName,
                        'phone' => l10n.commonPhone,
                        'carMake' => l10n.taxiCaptainCarMakeLabel,
                        'carModel' => l10n.taxiCaptainCarModelLabel,
                        _ => null,
                      };
                      backendErrors[entry.key] = resolveFormFieldError(
                        l10n: l10n,
                        field: entry.key,
                        code: entry.value,
                        fieldLabel: fieldLabel,
                      );
                    }
                  }
                  setDialogState(() {
                    submitting = false;
                    if (backendErrors.isNotEmpty) {
                      fieldErrors
                        ..clear()
                        ..addAll(backendErrors);
                      formError = resolveFormLevelError(
                        l10n,
                        code: parsed.formCode,
                        fallback: l10n.validationReviewRequiredFields,
                      );
                    } else {
                      formError = _err(e);
                    }
                  });
                  if (backendErrors.isNotEmpty) {
                    await scrollCoordinator.focusFirstError(const [
                      'fullName',
                      'phone',
                      'carMake',
                      'carModel',
                    ]);
                  }
                } catch (_) {
                  setDialogState(() {
                    submitting = false;
                    formError = l10n.errorsServerFailure;
                  });
                }
              }

              return AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
                ),
                child: AlertDialog(
                  title: Text(l10n.taxiCaptainProfileEditRequestTitle),
                  content: Directionality(
                    textDirection: context.appTextDirection,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FormErrorBanner(message: formError),
                          scrollCoordinator.anchor(
                            'fullName',
                            TextField(
                              controller: nameCtrl,
                              focusNode: scrollCoordinator.focusNodeFor(
                                'fullName',
                              ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) {
                                if (fieldErrors.containsKey('fullName') ||
                                    formError != null) {
                                  setDialogState(() {
                                    fieldErrors.remove('fullName');
                                    if (fieldErrors.isEmpty) formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: l10n.commonName,
                                errorText: fieldErrors['fullName'],
                              ),
                            ),
                          ),
                          scrollCoordinator.anchor(
                            'phone',
                            TextField(
                              controller: phoneCtrl,
                              focusNode: scrollCoordinator.focusNodeFor(
                                'phone',
                              ),
                              textInputAction: TextInputAction.next,
                              keyboardType: TextInputType.phone,
                              onChanged: (_) {
                                if (fieldErrors.containsKey('phone') ||
                                    formError != null) {
                                  setDialogState(() {
                                    fieldErrors.remove('phone');
                                    if (fieldErrors.isEmpty) formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: l10n.commonPhone,
                                errorText: fieldErrors['phone'],
                              ),
                            ),
                          ),
                          scrollCoordinator.anchor(
                            'carMake',
                            TextField(
                              controller: carMakeCtrl,
                              focusNode: scrollCoordinator.focusNodeFor(
                                'carMake',
                              ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) {
                                if (fieldErrors.containsKey('carMake') ||
                                    formError != null) {
                                  setDialogState(() {
                                    fieldErrors.remove('carMake');
                                    if (fieldErrors.isEmpty) formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: l10n.taxiCaptainCarMakeLabel,
                                errorText: fieldErrors['carMake'],
                              ),
                            ),
                          ),
                          scrollCoordinator.anchor(
                            'carModel',
                            TextField(
                              controller: carModelCtrl,
                              focusNode: scrollCoordinator.focusNodeFor(
                                'carModel',
                              ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) {
                                if (fieldErrors.containsKey('carModel') ||
                                    formError != null) {
                                  setDialogState(() {
                                    fieldErrors.remove('carModel');
                                    if (fieldErrors.isEmpty) formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: l10n.taxiCaptainCarModelLabel,
                                errorText: fieldErrors['carModel'],
                              ),
                            ),
                          ),
                          TextField(
                            controller: noteCtrl,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: l10n.mapPageOptionalNote,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: Text(l10n.commonCancel),
                    ),
                    FilledButton(
                      onPressed: submitting ? null : submit,
                      child: Text(l10n.commonSend),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (ok == true) {
        _snack(l10n.taxiCaptainProfileEditRequestSent);
      }
    } finally {
      scrollCoordinator.dispose();
      nameCtrl.dispose();
      phoneCtrl.dispose();
      carMakeCtrl.dispose();
      carModelCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Map<String, dynamic>? get _ride {
    return taxiRideViewFromEnvelope(_currentRideEnvelope);
  }

  Map<String, dynamic>? get _profileMap {
    final p = _profile?['profile'];
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  Map<String, dynamic>? get _sub {
    final s =
        _subscription?['subscription'] ??
        _profile?['subscription'] ??
        _dashboard?['subscription'];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  bool get _locked => _sub?['canAccess'] != true && _sub != null;

  @override
  /// يبني لوحة الكابتن كاملة، بما فيها الخريطة والرحلات الحالية ولوحة الملف.
  Widget build(BuildContext context) {
    final useDesktop = DesktopDashboardFrame.shouldUse(context);
    final pageTitle = _pageTitle();
    final pageSubtitle = _pageSubtitle();
    final drawerWidget = AppUserDrawer(
      title: pageTitle,
      subtitle: pageSubtitle,
      items: [
        AppUserDrawerItem(
          icon: Icons.local_taxi,
          label: _t('الرحلات الجديدة', 'New trips'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.newTrips),
        ),
        AppUserDrawerItem(
          icon: Icons.directions_car_filled_outlined,
          label: _t('الرحلات الحالية', 'Current trips'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.currentTrips),
        ),
        AppUserDrawerItem(
          icon: Icons.check_circle_outline_rounded,
          label: _t('الرحلات المكتملة', 'Completed trips'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.completedTrips),
        ),
        AppUserDrawerItem(
          icon: Icons.cancel_outlined,
          label: _t('الرحلات الملغاة', 'Cancelled trips'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.cancelledTrips),
        ),
        AppUserDrawerItem(
          icon: Icons.attach_money_rounded,
          label: _t('الأرباح', 'Earnings'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.earnings),
        ),
        AppUserDrawerItem(
          icon: Icons.insights_outlined,
          label: _t('التقارير', 'Reports'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.reports),
        ),
        AppUserDrawerItem(
          icon: Icons.account_balance_wallet_outlined,
          label: context.l10n.taxiCaptainLoyaltyTitle,
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TaxiCaptainLoyaltyScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.notifications_active_outlined,
          label: _t('الإشعارات', 'Notifications'),
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.person_outline_rounded,
          label: _t('الملف الشخصي', 'Profile'),
          onTap: (_) async =>
              _replaceCaptainView(TaxiCaptainDashboardIntent.profile),
        ),
        AppUserDrawerItem(
          icon: Icons.manage_accounts_outlined,
          label: _t('إعدادات الحساب', 'Account settings'),
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsAccountScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.support_agent_outlined,
          label: _t('الدعم', 'Support'),
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsSupportScreen(),
              ),
            );
          },
        ),
      ],
    );
    final bodyContent = IndexedStack(
      index: _tab,
      children: [_rideTab(), _dashboardTab(), _profileTab()],
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      drawer: useDesktop ? null : drawerWidget,
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          if (useDesktop)
            IconButton(
              tooltip: _t('الرحلات', 'Rides'),
              onPressed: () => _setTab(0),
              icon: const Icon(Icons.local_taxi),
            ),
          if (useDesktop)
            IconButton(
              tooltip: _t('اللوحة', 'Dashboard'),
              onPressed: () => _setTab(1),
              icon: const Icon(Icons.insights),
            ),
          if (useDesktop)
            IconButton(
              tooltip: _t('الملف الشخصي', 'Profile'),
              onPressed: () => _setTab(2),
              icon: const Icon(Icons.person),
            ),
          IconButton(
            onPressed: _sending
                ? null
                : () async {
                    await _refreshMeta();
                    await _tick(full: true);
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: useDesktop
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: DesktopDashboardFrame(
                sidebar: _DesktopCaptainSidebar(
                  captainName:
                      ref.read(authControllerProvider).user?.fullName ??
                      _t('كابتن التكسي', 'Taxi Captain'),
                  online: _online,
                  streamConnected: _streamConnected,
                  followMe: _followMe,
                  locked: _locked,
                  activeTab: _tab,
                  onSelectTab: _setTab,
                  onRefresh: _sending
                      ? null
                      : () async {
                          await _refreshMeta();
                          await _tick(full: true);
                        },
                  onToggleFollow: () => setState(() => _followMe = !_followMe),
                  onLogout: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
                title: pageTitle,
                subtitle: pageSubtitle,
                quickActions: [
                  DesktopQuickActionButton(
                    icon: Icons.local_taxi,
                    label: _t('الرحلات', 'Rides'),
                    selected: _tab == 0,
                    onPressed: () => _setTab(0),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.insights,
                    label: _t('اللوحة', 'Dashboard'),
                    selected: _tab == 1,
                    onPressed: () => _setTab(1),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.person,
                    label: _t('الملف الشخصي', 'Profile'),
                    selected: _tab == 2,
                    onPressed: () => _setTab(2),
                  ),
                  DesktopQuickActionButton(
                    icon: _followMe ? Icons.gps_fixed : Icons.gps_not_fixed,
                    label: _followMe
                        ? _t('تتبع الخريطة', 'Map Tracking')
                        : _t('وضع حر', 'Free Mode'),
                    selected: _followMe,
                    onPressed: () => setState(() => _followMe = !_followMe),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.refresh,
                    label: _t('تحديث', 'Refresh'),
                    onPressed: _sending
                        ? null
                        : () async {
                            await _refreshMeta();
                            await _tick(full: true);
                          },
                  ),
                ],
                child: bodyContent,
              ),
            )
          : bodyContent,
      bottomNavigationBar: useDesktop
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _setTab,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.local_taxi),
                  label: _t('الرحلات', 'Rides'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.insights),
                  label: _t('اللوحة', 'Dashboard'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person),
                  label: _t('الملف الشخصي', 'Profile'),
                ),
              ],
            ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => setState(() => _followMe = !_followMe),
              icon: Icon(_followMe ? Icons.gps_fixed : Icons.gps_not_fixed),
              label: Text(_followMe ? _t('تتبع', 'Track') : _t('حر', 'Free')),
            )
          : null,
    );
  }

  Widget _rideTab() {
    final status = _str(_ride?['status']);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(initialCenter: _center, initialZoom: 15.5),
          children: [
            TileLayer(
              urlTemplate:
                  'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              retinaMode:
                  (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0) > 1.0,
              fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.maslaki.bismayah',
              tileProvider: NetworkTileProvider(
                headers: {
                  'User-Agent': 'MaslakiTaxi/1.0 (+https://maslaki.app)',
                },
              ),
            ),
            if (_routePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 7,
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 4.4,
                    color: Colors.amberAccent.withValues(alpha: 0.95),
                  ),
                ],
              ),
            MarkerLayer(markers: _markers()),
          ],
        ),
        Positioned(top: 12, left: 12, right: 12, child: _topPanel()),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(child: _bottomPanel(status)),
        ),
      ],
    );
  }

  Widget _topPanel() {
    final t = _lastSync;
    final last = t == null
        ? '--:--'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xC01D1551), Color(0xAA040D2B)],
        ),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF53B8FF).withValues(alpha: 0.14),
            blurRadius: 16,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _streamConnected ? Icons.wifi : Icons.wifi_off,
                color: _streamConnected ? Colors.greenAccent : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                _streamConnected
                    ? _t('تحديث حي', 'Live update')
                    : _t('جارٍ إعادة الاتصال', 'Reconnecting'),
                style: const TextStyle(color: Colors.white),
              ),
              if (_routeLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              const Spacer(),
              Text(
                '${_t('آخر مزامنة', 'Last sync')}: $last',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                _t('متاح للطلبات', 'Available for requests'),
                style: const TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              Switch(value: _online, onChanged: _locked ? null : _setOnline),
            ],
          ),
          if (widget.initialIntent != TaxiCaptainDashboardIntent.defaultHome ||
              _focusedRideId != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _intentTitle(widget.initialIntent),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_focusedRideId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_t('رحلة مستهدفة', 'Focused ride')} #$_focusedRideId',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_locked)
            Text(
              _t(
                'الحساب موقوف بسبب الاشتراك',
                'Account locked by subscription',
              ),
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomPanel(String? status) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = (screenHeight * 0.44).clamp(250.0, 430.0).toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 220, maxHeight: panelHeight),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xD0121C61), Color(0xD01A2A6E)],
          ),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _locked
            ? SingleChildScrollView(child: _subscriptionCard(compact: false))
            : (_ride == null
                  ? (widget.initialIntent ==
                            TaxiCaptainDashboardIntent.currentTrips
                        ? _currentTripsEmptyPanel()
                        : _nearbyPanel())
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: _activeRidePanel(status),
                    )),
      ),
    );
  }

  Widget _activeRidePanel(String? status) {
    final ride = _ride!;
    final nonAvailable = _t('غير متوفر', 'Not available');
    final fare =
        _asInt(ride['finalFare']) ??
        _asInt(ride['agreedFareIqd']) ??
        _asInt(ride['proposedFareIqd']);
    final fareLabel = fare != null && fare > 0 ? _money(fare) : nonAvailable;
    final rideId = _asInt(ride['id']);
    final vehicle = ride['vehicle'] is Map
        ? Map<String, dynamic>.from(ride['vehicle'] as Map)
        : ride['captain'] is Map && (ride['captain'] as Map)['vehicle'] is Map
        ? Map<String, dynamic>.from((ride['captain'] as Map)['vehicle'] as Map)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rideId != null && rideId > 0
              ? '${_t('رحلة', 'Ride')} #$rideId'
              : _t('رحلة', 'Ride'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_t('الحالة', 'Status')}: ${_status(status)}',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          '${_t('من', 'From')}: ${_str(ride['pickup']?['label']) ?? nonAvailable}',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          '${_t('إلى', 'To')}: ${_str(ride['dropoff']?['label']) ?? nonAvailable}',
          style: const TextStyle(color: Colors.white70),
        ),
        if (_distanceEtaSummary(ride) != null)
          Text(
            _distanceEtaSummary(ride)!,
            style: const TextStyle(color: Colors.white70),
          ),
        Text(
          '${_t('الأجرة', 'Fare')}: $fareLabel',
          style: const TextStyle(color: Colors.greenAccent),
        ),
        if (vehicle != null)
          Text(
            [
              _str(vehicle['vehicleMake']),
              _str(vehicle['vehicleModel']),
              _asInt(vehicle['vehicleYear'])?.toString(),
              _str(vehicle['vehicleColor']),
              _str(vehicle['vehiclePlate']),
            ].whereType<String>().where((item) => item.isNotEmpty).join(' • '),
            style: const TextStyle(color: Colors.white70),
          ),
        Text(
          '${_t('النطاق التقديري للنظام', 'System estimate range')}: ${_systemEstimateLabel(ride)}',
          style: const TextStyle(color: Colors.lightBlueAccent),
        ),
        if (_couponCaptainSummary(ride) != null)
          Text(
            _couponCaptainSummary(ride)!,
            style: const TextStyle(color: Colors.amberAccent),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _sending
                  ? null
                  : () {
                      final pickup = _latLng(ride['pickup']);
                      if (pickup == null) return;
                      _openInWaze(
                        destination: pickup,
                        targetLabel: _t('موقع الزبون', 'Customer location'),
                      );
                    },
              icon: const Icon(Icons.person_pin_circle_rounded),
              label: Text(_t('فتح موقع الزبون', 'Open customer location')),
            ),
            FilledButton.tonalIcon(
              onPressed: _sending
                  ? null
                  : () {
                      final dropoff = _latLng(ride['dropoff']);
                      if (dropoff == null) return;
                      _openInWaze(
                        destination: dropoff,
                        targetLabel: _t('نقطة الوصول', 'Dropoff point'),
                      );
                    },
              icon: const Icon(Icons.flag_rounded),
              label: Text(_t('فتح موقع الوصول', 'Open dropoff point')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (status == 'captain_assigned' ||
            status == 'captain_arriving' ||
            status == 'ride_started') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: rideId == null || rideId <= 0
                    ? null
                    : () => _openRideChatBottomSheet(rideId),
                icon: const Icon(Icons.chat_rounded),
                label: Text(_t('دردشة', 'Chat')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (status == 'captain_assigned')
          FilledButton(
            onPressed: _sending ? null : () => _advance('arrive'),
            child: Text(_t('التوجّه إلى الزبون', 'Head to customer')),
          ),
        if (status == 'captain_arriving')
          FilledButton(
            onPressed: _sending ? null : () => _advance('start'),
            child: Text(_t('بدء الرحلة', 'Start ride')),
          ),
        if (status == 'ride_started')
          FilledButton(
            onPressed: _sending ? null : () => _advance('complete'),
            child: Text(_t('إنهاء الرحلة', 'End ride')),
          ),
      ],
    );
  }

  Widget _nearbyPanel() {
    final focusedRideId = _focusedRideId;
    final nearby = List<Map<String, dynamic>>.from(_nearby);
    if (focusedRideId != null) {
      nearby.sort((a, b) {
        final aMatch = _asInt(a['id']) == focusedRideId ? 0 : 1;
        final bMatch = _asInt(b['id']) == focusedRideId ? 0 : 1;
        if (aMatch != bMatch) return aMatch - bMatch;
        return (_asInt(b['id']) ?? 0).compareTo(_asInt(a['id']) ?? 0);
      });
    }

    final focusedSnapshotId = _asInt(_focusedRideSnapshot?['id']);
    final showFocusedSnapshotCard =
        _focusedRideSnapshot != null &&
        focusedSnapshotId != null &&
        !nearby.any((item) => _asInt(item['id']) == focusedSnapshotId);
    final hasNearby = nearby.isNotEmpty;
    final showFallback = _focusedRideUnavailable;

    if (!hasNearby && !showFocusedSnapshotCard && !showFallback) {
      return Center(
        child: Text(
          _t('لا توجد طلبات ضمن نطاقك', 'No requests within your range'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFallback) _focusedRideUnavailableCard(),
        if (showFallback && (showFocusedSnapshotCard || hasNearby))
          const SizedBox(height: 8),
        if (showFocusedSnapshotCard) ...[
          _focusedRideSnapshotCard(_focusedRideSnapshot!),
          if (hasNearby) const SizedBox(height: 8),
        ],
        if (hasNearby)
          Expanded(
            child: ListView.separated(
              itemCount: nearby.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = nearby[i];
                final nonAvailable = _t('غير متوفر', 'Not available');
                final fare = _asInt(r['proposedFareIqd']);
                final fareLabel = fare != null && fare > 0
                    ? _money(fare)
                    : nonAvailable;
                final myBid = r['myBid'] is Map
                    ? Map<String, dynamic>.from(r['myBid'] as Map)
                    : null;
                final myBidId = _asInt(myBid?['id']);
                final currentBidId = _asInt(r['currentBidId']);
                final isCurrentNegotiationBid =
                    myBidId != null &&
                    currentBidId != null &&
                    myBidId == currentBidId;
                final queueTag = myBid == null
                    ? _t('جديد', 'New')
                    : isCurrentNegotiationBid
                    ? _t('دورك الآن', 'Your turn now')
                    : _t('بانتظار الدور', 'Waiting turn');
                final queueColor = myBid == null
                    ? Colors.lightGreenAccent
                    : isCurrentNegotiationBid
                    ? Colors.orangeAccent
                    : Colors.white70;
                final negotiationRemaining = _negotiationRemainingSeconds(
                  r,
                  myBid,
                );
                final negotiationProgress = negotiationRemaining == null
                    ? null
                    : (negotiationRemaining / 300).clamp(0.0, 1.0).toDouble();
                final rideId = _asInt(r['id']);
                final isFocused =
                    focusedRideId != null &&
                    rideId != null &&
                    rideId == focusedRideId;
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused
                          ? Colors.orangeAccent.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.1),
                      width: isFocused ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rideId != null && rideId > 0
                                  ? '${_t('الطلب', 'Request')} #$rideId'
                                  : _t('الطلب', 'Request'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isFocused)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _t('مستهدفة', 'Focused'),
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: queueColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              queueTag,
                              style: TextStyle(
                                color: queueColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_t('من', 'From')}: ${_str(r['pickup']?['label']) ?? nonAvailable}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        '${_t('إلى', 'To')}: ${_str(r['dropoff']?['label']) ?? nonAvailable}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${_t('أجرة الزبون', 'Customer fare')}: $fareLabel',
                            style: const TextStyle(color: Colors.greenAccent),
                          ),
                          const Spacer(),
                          if (myBid != null)
                            Builder(
                              builder: (_) {
                                final myBidFare = _asInt(
                                  myBid['offeredFareIqd'],
                                );
                                final myBidFareLabel =
                                    myBidFare != null && myBidFare > 0
                                    ? _money(myBidFare)
                                    : nonAvailable;
                                return Text(
                                  '${_t('عرضك', 'Your offer')}: $myBidFareLabel',
                                  style: const TextStyle(
                                    color: Colors.lightBlueAccent,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      Text(
                        '${_t('النطاق التقديري للنظام', 'System estimate range')}: ${_systemEstimateLabel(r)}',
                        style: const TextStyle(color: Colors.lightBlueAccent),
                      ),
                      if (_distanceEtaSummary(r) != null)
                        Text(
                          _distanceEtaSummary(r)!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      if (_couponCaptainSummary(r) != null)
                        Text(
                          _couponCaptainSummary(r)!,
                          style: const TextStyle(color: Colors.amberAccent),
                        ),
                      if (negotiationRemaining != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _t(
                                  'الوقت المتبقي للتفاوض',
                                  'Remaining negotiation time',
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _countdownText(negotiationRemaining),
                              style: TextStyle(
                                color: negotiationRemaining <= 15
                                    ? Colors.redAccent
                                    : Colors.orangeAccent,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: negotiationProgress,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(999),
                          backgroundColor: Colors.white12,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if ((_asInt(r['proposedFareIqd']) ?? 0) > 0)
                            FilledButton.icon(
                              onPressed: _sending
                                  ? null
                                  : () => _acceptCustomerFare(r),
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                _t('قبول السعر', 'Accept customer fare'),
                              ),
                            ),
                          FilledButton.tonal(
                            onPressed: _sending ? null : () => _submitBid(r),
                            child: Text(
                              myBid == null
                                  ? _t('إرسال العرض', 'Send Offer')
                                  : _t('تعديل عرضي', 'Edit My Offer'),
                            ),
                          ),
                          if (myBid == null)
                            OutlinedButton.icon(
                              onPressed: _sending
                                  ? null
                                  : () => _declineRideRequest(r),
                              icon: const Icon(Icons.close_rounded),
                              label: Text(_t('رفض الطلب', 'Decline request')),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _focusedRideUnavailableCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(
                'لم تعد الرحلة المستهدفة متاحة. يمكنك التحديث أو متابعة الطلبات الحالية.',
                'Focused ride is no longer available. Refresh or continue with current requests.',
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton.icon(
            onPressed: _sending
                ? null
                : () async {
                    await _tick(full: true);
                  },
            icon: const Icon(Icons.refresh),
            label: Text(_t('تحديث', 'Refresh')),
          ),
        ],
      ),
    );
  }

  Widget _focusedRideSnapshotCard(Map<String, dynamic> ride) {
    final nonAvailable = _t('غير متوفر', 'Not available');
    final fare =
        _asInt(ride['agreedFareIqd']) ?? _asInt(ride['proposedFareIqd']);
    final fareLabel = fare != null && fare > 0 ? _money(fare) : nonAvailable;
    final status = _status(_str(ride['status']));
    final rideId = _asInt(ride['id']);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rideId != null && rideId > 0
                      ? '${_t('رحلة محددة', 'Selected ride')} #$rideId'
                      : _t('رحلة محددة', 'Selected ride'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _sending || rideId == null || rideId <= 0
                    ? null
                    : () async {
                        await _focusRideById(
                          rideId,
                          showUnavailableMessage: true,
                        );
                      },
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t('إعادة التحقق', 'Recheck')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_t('الحالة', 'Status')}: $status',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            '${_t('من', 'From')}: ${_str(ride['pickup']?['label']) ?? nonAvailable}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            '${_t('إلى', 'To')}: ${_str(ride['dropoff']?['label']) ?? nonAvailable}',
            style: const TextStyle(color: Colors.white70),
          ),
          if (_distanceEtaSummary(ride) != null)
            Text(
              _distanceEtaSummary(ride)!,
              style: const TextStyle(color: Colors.white70),
            ),
          Text(
            '${_t('الأجرة', 'Fare')}: $fareLabel',
            style: const TextStyle(color: Colors.greenAccent),
          ),
          Text(
            '${_t('النطاق التقديري للنظام', 'System estimate range')}: ${_systemEstimateLabel(ride)}',
            style: const TextStyle(color: Colors.lightBlueAccent),
          ),
          if (_couponCaptainSummary(ride) != null)
            Text(
              _couponCaptainSummary(ride)!,
              style: const TextStyle(color: Colors.amberAccent),
            ),
        ],
      ),
    );
  }

  Widget _currentTripsEmptyPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_focusedRideUnavailable) _focusedRideUnavailableCard(),
            if (_focusedRideUnavailable) const SizedBox(height: 8),
            if (_focusedRideSnapshot != null) ...[
              _focusedRideSnapshotCard(_focusedRideSnapshot!),
              const SizedBox(height: 10),
            ],
            Text(
              _t(
                'لا توجد رحلة نشطة حالياً ضمن صفحة الرحلات الحالية.',
                'There is no active ride right now in Current trips view.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      _replaceCaptainView(TaxiCaptainDashboardIntent.newTrips),
                  icon: const Icon(Icons.local_taxi_rounded),
                  label: Text(_t('عرض الرحلات الجديدة', 'Open new trips')),
                ),
                OutlinedButton.icon(
                  onPressed: _sending
                      ? null
                      : () async {
                          await _tick(full: true);
                        },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_t('تحديث الآن', 'Refresh now')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardTab() {
    final m = (_dashboard?['metrics'] is Map)
        ? Map<String, dynamic>.from(_dashboard!['metrics'] as Map)
        : <String, dynamic>{};
    final history = (_dashboard?['history'] is List)
        ? _toMapList(_dashboard!['history'])
        : const <Map<String, dynamic>>[];
    final filteredHistory = _dashboardHistoryFilterStatus == null
        ? history
        : history
              .where(
                (item) => _str(item['status']) == _dashboardHistoryFilterStatus,
              )
              .toList(growable: false);

    int rides(String k) => _asInt((m[k] as Map?)?['ridesCount']) ?? 0;
    int earn(String k) => _asInt((m[k] as Map?)?['earningsIqd']) ?? 0;

    return Directionality(
      textDirection: context.appTextDirection,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _captainQuickTabs(currentTab: _tab, onSelectTab: _setTab),
          const SizedBox(height: 10),
          _subscriptionCard(compact: true),
          const SizedBox(height: 10),
          _metricCard(
            _t('اليوم', 'Today'),
            rides('day'),
            earn('day'),
            onTap: () => _switchDashboardPeriod('day'),
          ),
          _metricCard(
            _t('الأسبوع', 'Week'),
            rides('week'),
            earn('week'),
            onTap: () => _switchDashboardPeriod('week'),
          ),
          _metricCard(
            _t('الشهر', 'Month'),
            rides('month'),
            earn('month'),
            onTap: () => _switchDashboardPeriod('month'),
          ),
          _metricCard(
            _t('الإجمالي', 'Total'),
            rides('total'),
            earn('total'),
            onTap: () => _switchDashboardPeriod('all'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _periodChip('day', _t('اليوم', 'Today')),
              _periodChip('week', _t('الأسبوع', 'Week')),
              _periodChip('month', _t('الشهر', 'Month')),
              _periodChip('all', _t('الكل', 'All')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _t('سجل الرحلات', 'Ride history'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_dashboardHistoryFilterStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_t('تصفية الحالة', 'Status filter')}: ${_status(_dashboardHistoryFilterStatus)}',
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          const SizedBox(height: 6),
          if (filteredHistory.isEmpty)
            Text(
              _t('لا توجد رحلات في هذه الفترة', 'No rides in this period'),
              style: const TextStyle(color: Colors.white70),
            )
          else
            ...filteredHistory.map(
              (r) => ListTile(
                onTap: () async {
                  final rideId = _asInt(r['id']);
                  if (rideId == null || rideId <= 0) return;
                  await _replaceCaptainView(
                    TaxiCaptainDashboardIntent.tripDetails,
                    rideId: rideId,
                  );
                },
                title: Text(
                  '${_t('رحلة', 'Ride')} #${r['id']}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${_status(_str(r['status']))} - ${_str(r['createdAt']) ?? ''}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Text(
                  _money(
                    _asInt(r['agreedFareIqd']) ??
                        _asInt(r['proposedFareIqd']) ??
                        0,
                  ),
                  style: const TextStyle(color: Colors.greenAccent),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileTab() {
    final p = _profileMap;
    return Directionality(
      textDirection: context.appTextDirection,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _captainQuickTabs(currentTab: _tab, onSelectTab: _setTab),
          const SizedBox(height: 10),
          _subscriptionCard(compact: false),
          const SizedBox(height: 10),
          _profileRow(_t('الاسم', 'Name'), _str(p?['fullName']) ?? '-'),
          _profileRow(_t('الهاتف', 'Phone'), _str(p?['phone']) ?? '-'),
          _profileRow(_t('البلوك', 'Block'), _str(p?['block']) ?? '-'),
          _profileRow(
            _t('البناية', 'Building'),
            _str(p?['buildingNumber']) ?? '-',
          ),
          _profileRow(_t('الشقة', 'Apartment'), _str(p?['apartment']) ?? '-'),
          const Divider(color: Colors.white24),
          _profileRow(
            _t('نوع السيارة', 'Car Make'),
            _str(p?['carMake']) ?? '-',
          ),
          _profileRow(_t('الموديل', 'Model'), _str(p?['carModel']) ?? '-'),
          _profileRow(_t('السنة', 'Year'), _str(p?['carYear']) ?? '-'),
          _profileRow(_t('اللوحة', 'Plate'), _str(p?['plateNumber']) ?? '-'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _requestProfileEdit,
            icon: const Icon(Icons.edit_note),
            label: Text(
              _t(
                'طلب تعديل البيانات (موافقة الأدمن)',
                'Request Profile Edit (Admin Approval)',
              ),
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.amber)),
        ],
      ),
    );
  }

  Widget _subscriptionCard({required bool compact}) {
    final s = _sub;
    final can = s?['canAccess'] == true;
    final pending = s?['cashPaymentPending'] == true;
    final days = _asInt(s?['remainingDays']) ?? 0;
    final fee = _asInt(s?['discountedMonthlyFeeIqd']) ?? 10000;
    final discount = _asInt(s?['discountPercent']) ?? 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: can
            ? Colors.teal.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            can
                ? _t('الاشتراك فعال', 'Subscription active')
                : (pending
                      ? _t('بانتظار اعتماد التسديد', 'Payment approval pending')
                      : _t('الاشتراك منتهي', 'Subscription expired')),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            can
                ? '${_t('المتبقي', 'Remaining')}: $days ${_t('يوم', 'days')}'
                : '${_t('المبلغ المطلوب', 'Required amount')}: ${_money(fee)}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            '${_t('الخصم', 'Discount')}: $discount%',
            style: const TextStyle(color: Colors.white70),
          ),
          if (!can)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                onPressed: (pending || _sending) ? null : _requestCashPayment,
                child: Text(
                  pending
                      ? _t('تم إرسال طلب التسديد', 'Payment request submitted')
                      : _t('طلب تسديد نقدي', 'Request cash payment'),
                ),
              ),
            ),
          if (!compact && can && days <= 7)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _t(
                  'تنبيه: بقي أقل من أسبوع على انتهاء الاشتراك',
                  'Alert: less than one week left on subscription',
                ),
                style: const TextStyle(color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricCard(
    String title,
    int rides,
    int earnings, {
    VoidCallback? onTap,
  }) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '${_t('الرحلات', 'Rides')}: $rides',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Text(
            _money(earnings),
            style: const TextStyle(color: Colors.greenAccent),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _period == value,
      onSelected: (_) => _switchDashboardPeriod(value),
    );
  }

  Widget _captainQuickTabs({
    required int currentTab,
    required ValueChanged<int> onSelectTab,
  }) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _captainQuickTabChip(
            label: _t('الرحلات', 'Rides'),
            selected: currentTab == 0,
            onTap: () => onSelectTab(0),
          ),
          const SizedBox(width: 8),
          _captainQuickTabChip(
            label: _t('اللوحة', 'Dashboard'),
            selected: currentTab == 1,
            onTap: () => onSelectTab(1),
          ),
          const SizedBox(width: 8),
          _captainQuickTabChip(
            label: _t('الملف الشخصي', 'Profile'),
            selected: currentTab == 2,
            onTap: () => onSelectTab(2),
          ),
        ],
      ),
    );
  }

  Widget _captainQuickTabChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? const Color(0xFF53B8FF).withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF53B8FF) : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers() {
    final list = <Marker>[];
    final rideForMarkers = _ride ?? _focusedRideSnapshot;
    final pickup = _latLng(rideForMarkers?['pickup']);
    final dropoff = _latLng(rideForMarkers?['dropoff']);
    if (pickup != null) {
      list.add(
        Marker(
          point: pickup,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.trip_origin,
            color: Colors.greenAccent,
            size: 30,
          ),
        ),
      );
    }
    if (dropoff != null) {
      list.add(
        Marker(
          point: dropoff,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.redAccent,
            size: 32,
          ),
        ),
      );
    }
    if (_captainPoint != null) {
      list.add(
        Marker(
          point: _captainPoint!,
          width: 46,
          height: 46,
          child: const Icon(Icons.local_taxi, color: Colors.white, size: 34),
        ),
      );
    }
    return list;
  }

  LatLng? _latLng(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final lat = _asDouble(m['latitude']) ?? _asDouble(m['lat']);
    final lng = _asDouble(m['longitude']) ?? _asDouble(m['lng']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  List<Map<String, dynamic>> _toMapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int? _asInt(dynamic v) => v is int ? v : tryParseLocalizedInt(v);
  double? _asDouble(dynamic v) =>
      v is num ? v.toDouble() : tryParseLocalizedDouble(v);
  DateTime? _asDate(dynamic v) {
    final t = _str(v);
    if (t == null || t.isEmpty) return null;
    return DateTime.tryParse(t);
  }

  int? _negotiationRemainingSeconds(
    Map<String, dynamic> ride,
    Map<String, dynamic>? myBid,
  ) {
    if (myBid == null) return null;
    final myBidId = _asInt(myBid['id']);
    final currentBidId = _asInt(ride['currentBidId']);
    if (myBidId == null || currentBidId == null || myBidId != currentBidId) {
      return null;
    }
    final timeoutSeconds = 300;
    final anchor = _asDate(myBid['updatedAt']) ?? _asDate(myBid['createdAt']);
    if (anchor == null) return null;
    final expiresAt = anchor.add(Duration(seconds: timeoutSeconds));
    final seconds = expiresAt.difference(DateTime.now()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  String _countdownText(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String? _str(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  String _money(int n) {
    final s = n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return '$s IQD';
  }

  TaxiFareEstimateRange _systemEstimateForRide(Map<String, dynamic> ride) {
    final pickup = _latLng(ride['pickup']);
    final dropoff = _latLng(ride['dropoff']);
    if (pickup == null || dropoff == null) {
      return TaxiFarePolicy.estimateFromDistanceMeters(null);
    }
    final distanceM = _routeService.distanceMeters(pickup, dropoff);
    final durationSeconds = ((distanceM / 1000) / 35 * 3600).round();
    return TaxiFarePolicy.estimateFromDistanceMeters(
      distanceM,
      durationSeconds: durationSeconds,
    );
  }

  String _systemEstimateLabel(Map<String, dynamic> ride) {
    final est = _systemEstimateForRide(ride);
    return '${_money(est.lowIqd)} - ${_money(est.highIqd)}';
  }

  String? _distanceEtaSummary(Map<String, dynamic> ride) {
    var distanceM =
        _asInt(ride['estimatedDistanceM']) ?? _asInt(ride['distanceMeters']);
    var durationSeconds =
        _asInt(ride['estimatedDurationS']) ??
        _asInt(ride['estimatedDurationSeconds']) ??
        _asInt(ride['etaSeconds']);

    if (distanceM == null || distanceM <= 0) {
      final pickup = _latLng(ride['pickup']);
      final dropoff = _latLng(ride['dropoff']);
      if (pickup != null && dropoff != null) {
        distanceM = _routeService.distanceMeters(pickup, dropoff).round();
      }
    }

    if ((durationSeconds == null || durationSeconds <= 0) &&
        distanceM != null &&
        distanceM > 0) {
      durationSeconds = ((distanceM / 1000) / 35 * 3600).round();
    }

    if (distanceM == null || distanceM <= 0 || durationSeconds == null) {
      return null;
    }
    final distanceKm = distanceM / 1000.0;
    final distanceText = distanceKm >= 10
        ? distanceKm.toStringAsFixed(0)
        : distanceKm.toStringAsFixed(1);
    final etaMinutes = (durationSeconds / 60).ceil().clamp(1, 1440);
    return _t(
      'المسافة $distanceText كم • ETA $etaMinutes دقيقة',
      'Distance $distanceText km • ETA $etaMinutes min',
    );
  }

  String? _couponCaptainSummary(Map<String, dynamic> ride) {
    final couponCode =
        _str(ride['couponCodeSnapshot']) ?? _str(ride['couponCode']);
    final discount = _asInt(ride['couponDiscountIqd']) ?? 0;
    if ((couponCode == null || couponCode.isEmpty) && discount <= 0) {
      return null;
    }
    if (discount > 0) {
      return _t(
        'القسيمة $couponCode • خصم ${_money(discount)} (يتحمّله النظام ويُسوّى للكابتن ضمن الاشتراك)',
        'Coupon $couponCode • discount ${_money(discount)} (covered by system and settled to captain subscription)',
      );
    }
    return _t(
      'يوجد كوبون على الرحلة (الخصم يتحمله النظام)',
      'This ride has a coupon (system-covered discount).',
    );
  }

  String _status(String? s) {
    switch (s) {
      case 'searching':
        return _t('جارٍ البحث عن كابتن', 'Searching for captain');
      case 'captain_assigned':
        return _t('تم تعيين الكابتن', 'Captain assigned');
      case 'captain_arriving':
        return _t('في الطريق إلى الزبون', 'On the way to customer');
      case 'ride_started':
        return _t('الرحلة قيد التنفيذ', 'Ride in progress');
      case 'completed':
        return _t('مكتملة', 'Completed');
      case 'cancelled':
        return _t('ملغاة', 'Cancelled');
      case 'expired':
        return _t('منتهية', 'Expired');
      default:
        return _t('غير معروف', 'Unknown');
    }
  }

  String _err(DioException e) {
    return mapDioError(
      e,
      fallback: _t(
        'تعذر الوصول إلى الخادم. حاول مرة أخرى.',
        'Unable to reach server. Please try again.',
      ),
      customMessages: {
        'DELIVERY_SUBSCRIPTION_EXPIRED': _t(
          'انتهى الاشتراك. يرجى طلب تسديد نقدي.',
          'Subscription expired. Please request cash payment.',
        ),
        'DELIVERY_SUBSCRIPTION_PAYMENT_PENDING': _t(
          'تم إرسال طلب التسديد. بانتظار موافقة الإدارة.',
          'Payment request sent. Waiting for admin approval.',
        ),
        'DELIVERY_ACCOUNT_PENDING_APPROVAL': _t(
          'الحساب بانتظار موافقة الإدارة.',
          'Account is pending admin approval.',
        ),
        'TAXI_CHAT_CLOSED': _t(
          'الدردشة متاحة فقط أثناء التفاوض أو الرحلة النشطة.',
          'Taxi chat is available only during negotiation or an active trip.',
        ),
        'TAXI_RIDE_ALREADY_DECLINED': _t(
          'سبق أن رفضت هذا الطلب.',
          'You already declined this request.',
        ),
        'TAXI_CAPTAIN_ALREADY_HAS_BID': _t(
          'لديك عرض قائم على هذا الطلب. عدّل عرضك بدل رفضه.',
          'You already have a bid on this request. Edit it instead of declining.',
        ),
      },
      appendRequestId: true,
    );
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  double? _sanitizeHeading(double v) =>
      (v.isFinite && v >= 0 && v <= 360) ? v : null;
  double? _sanitizeSpeed(double v) => (v.isFinite && v >= 0) ? v * 3.6 : null;
}
