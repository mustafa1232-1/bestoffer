// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../auth/state/auth_controller.dart';
import '../data/taxi_api.dart';
import '../../../pages/map_page.dart';

final taxiCustomerToolsApiProvider = Provider<TaxiApi>(
  (ref) => TaxiApi(ref.read(dioClientProvider).dio),
);

TaxiApi _taxiApi(WidgetRef ref) => ref.read(taxiCustomerToolsApiProvider);

const LatLng _defaultPickerCenter = LatLng(33.3128, 44.3615);

class TaxiCustomerToolsScreen extends ConsumerWidget {
  final int initialTab;
  const TaxiCustomerToolsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxiSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.taxi, displayName: 'التكسي');
    if (taxiSection.isBlocked) {
      return SectionUnavailableScreen(entry: taxiSection);
    }

    final l10n = context.l10n;
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab.clamp(0, 4),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.taxiToolsTitle),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.taxiSavedPlacesTitle),
              Tab(text: l10n.taxiFavoriteTripsTitle),
              Tab(text: l10n.taxiScheduledRidesTitle),
              const Tab(text: 'رحلاتي'),
              Tab(text: l10n.taxiMyCouponsTitle),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SavedPlacesTab(),
            _FavoriteTripsTab(),
            _ScheduledRidesTab(),
            _RideHistoryTab(),
            _MyCouponsTab(),
          ],
        ),
      ),
    );
  }
}

class _SavedPlaceDraft {
  final String label;
  final String placeType;
  final String addressText;
  final double latitude;
  final double longitude;

  const _SavedPlaceDraft({
    required this.label,
    required this.placeType,
    required this.addressText,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'placeType': placeType,
    'addressText': addressText,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class _SavedPlacesTab extends ConsumerStatefulWidget {
  const _SavedPlacesTab();

  @override
  ConsumerState<_SavedPlacesTab> createState() => _SavedPlacesTabState();
}

class _SavedPlacesTabState extends ConsumerState<_SavedPlacesTab> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _taxiApi(ref).listSavedPlaces();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.taxiSavedPlacesLoadFailed,
        );
      });
    }
  }

  Future<void> _importAddresses() async {
    final l10n = context.l10n;
    try {
      await _taxiApi(ref).importSavedPlacesFromDeliveryAddresses();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.taxiSavedPlacesImported)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyErrorL10n(
              error,
              fallbackBuilder: (l10n) => l10n.taxiSavedPlaceSaveFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _createPlace() async {
    final l10n = context.l10n;
    final draft = await Navigator.of(context).push<_SavedPlaceDraft>(
      MaterialPageRoute(builder: (_) => const _SavedPlaceEditorScreen()),
    );
    if (!mounted || draft == null) return;

    setState(() => _submitting = true);
    try {
      await _taxiApi(ref).createSavedPlace(draft.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.taxiSavedPlaceSaved)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyErrorL10n(
              error,
              fallbackBuilder: (l10n) => l10n.taxiSavedPlaceSaveFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  IconData _iconForPlaceType(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.business_center_rounded;
      default:
        return Icons.place_outlined;
    }
  }

  Future<void> _handleSavedPlaceAction(
    Map<String, dynamic> item,
    String value,
  ) async {
    final id = int.tryParse('${item['id']}');
    if (value == 'pickup') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MapPage(initialPickupSnapshot: item)),
      );
      return;
    }
    if (value == 'dropoff') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MapPage(initialDropoffSnapshot: item)),
      );
      return;
    }
    if (value == 'delete' && id != null) {
      await _taxiApi(ref).deleteSavedPlace(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.taxiSavedPlaceDeleted)),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorCard(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: MaslakiOutlineButton(
                  onPressed: _submitting ? null : _importAddresses,
                  icon: Icons.download_rounded,
                  label: l10n.taxiSavedPlacesImport,
                ),
              ),
              const SizedBox(width: MaslakiSpacing.sm),
              Expanded(
                child: MaslakiPrimaryButton(
                  onPressed: _submitting ? null : _createPlace,
                  icon: Icons.add_location_alt_rounded,
                  label: l10n.taxiSavedPlacesAddAction,
                ),
              ),
            ],
          ),
          const SizedBox(height: MaslakiSpacing.lg),
          if (_items.isEmpty)
            MaslakiEmptyState(
              icon: Icons.place_outlined,
              title: 'لا توجد أماكن محفوظة بعد',
              body:
                  'احفظ المنزل أو العمل أو أي نقطة مهمة من الخريطة لتصل لها بسرعة في المشاوير القادمة.',
              action: MaslakiPrimaryButton(
                onPressed: _submitting ? null : _createPlace,
                icon: Icons.add_location_alt_rounded,
                label: l10n.taxiSavedPlacesAddAction,
              ),
            ),
          for (final item in _items) ...[
            MaslakiCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: context.maslakiTokens.primaryAccent
                      .withValues(alpha: 0.12),
                  child: Icon(
                    _iconForPlaceType(item['placeType']?.toString()),
                    color: context.maslakiTokens.primaryAccent,
                  ),
                ),
                title: Text(item['label']?.toString() ?? '-'),
                subtitle: Text(item['addressText']?.toString() ?? '-'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _handleSavedPlaceAction(item, value),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pickup',
                      child: Text(l10n.taxiToolsOpenAsPickup),
                    ),
                    PopupMenuItem(
                      value: 'dropoff',
                      child: Text(l10n.taxiToolsOpenAsDropoff),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MaslakiSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FavoriteTripsTab extends ConsumerStatefulWidget {
  const _FavoriteTripsTab();

  @override
  ConsumerState<_FavoriteTripsTab> createState() => _FavoriteTripsTabState();
}

class _FavoriteTripsTabState extends ConsumerState<_FavoriteTripsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _taxiApi(ref).listFavoriteTrips();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.taxiFavoriteTripsLoadFailed,
        );
      });
    }
  }

  Future<void> _useTrip(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPage(
          initialPickupSnapshot:
              (item['pickupSnapshot'] as Map?)?.cast<String, dynamic>(),
          initialDropoffSnapshot:
              (item['dropoffSnapshot'] as Map?)?.cast<String, dynamic>(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorCard(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        children: [
          if (_items.isEmpty)
            const MaslakiEmptyState(
              icon: Icons.route_outlined,
              title: 'لا توجد رحلات مفضلة بعد',
              body:
                  'احفظ مساراتك المتكررة لتكرارها بسرعة من هنا أو من الصفحة الرئيسية لاحقًا.',
            ),
          for (final item in _items) ...[
            MaslakiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item['label']?.toString() ?? '-',
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  Text(
                    '${(item['pickupSnapshot'] as Map?)?['label'] ?? '-'} → ${(item['dropoffSnapshot'] as Map?)?['label'] ?? '-'}',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: MaslakiSpacing.md),
                  MaslakiPrimaryButton(
                    onPressed: () => _useTrip(item),
                    icon: Icons.local_taxi_rounded,
                    label: l10n.taxiFavoriteTripUseNow,
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ScheduledRidesTab extends ConsumerStatefulWidget {
  const _ScheduledRidesTab();

  @override
  ConsumerState<_ScheduledRidesTab> createState() => _ScheduledRidesTabState();
}

class _ScheduledRidesTabState extends ConsumerState<_ScheduledRidesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _taxiApi(ref).listScheduledRides(status: 'all');
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.taxiScheduledRidesLoadFailed,
        );
      });
    }
  }

  Future<void> _cancelRide(Map<String, dynamic> item) async {
    final id = int.tryParse('${item['id']}');
    if (id == null) return;
    await _taxiApi(ref).cancelScheduledRide(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.taxiScheduledRideCancelSuccess)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorCard(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        children: [
          if (_items.isEmpty)
            MaslakiEmptyState(
              icon: Icons.event_note_outlined,
              title: 'لا توجد رحلات مجدولة',
              body: l10n.taxiScheduledRidesEmpty,
            ),
          for (final item in _items) ...[
            MaslakiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(item['pickupSnapshot'] as Map?)?['label'] ?? '-'} → ${(item['dropoffSnapshot'] as Map?)?['label'] ?? '-'}',
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  Text(
                    '${l10n.commonStatus}: ${item['status'] ?? '-'}',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.taxiScheduledRidesWhen}: ${item['scheduleFor'] ?? '-'}',
                    textDirection: TextDirection.rtl,
                  ),
                  if (item['status'] == 'scheduled' ||
                      item['status'] == 'pending_dispatch') ...[
                    const SizedBox(height: MaslakiSpacing.md),
                    MaslakiOutlineButton(
                      onPressed: () => _cancelRide(item),
                      icon: Icons.cancel_outlined,
                      label: l10n.taxiScheduledRideCancelAction,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _RideHistoryTab extends ConsumerStatefulWidget {
  const _RideHistoryTab();

  @override
  ConsumerState<_RideHistoryTab> createState() => _RideHistoryTabState();
}

class _RideHistoryTabState extends ConsumerState<_RideHistoryTab> {
  bool _loading = true;
  bool _rebooking = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _taxiApi(ref).listMyRideHistory(
        period: 'all',
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحميل الرحلات السابقة.',
        );
      });
    }
  }

  Map<String, dynamic> _snapshotFromRidePoint(Map<String, dynamic>? point) {
    final map = point ?? const <String, dynamic>{};
    return <String, dynamic>{
      'latitude': tryParseLocalizedDouble(map['latitude']) ?? 0,
      'longitude': tryParseLocalizedDouble(map['longitude']) ?? 0,
      'label': map['label']?.toString() ?? '',
      'addressText': map['label']?.toString() ?? '',
    };
  }

  Future<void> _reuseRoute(Map<String, dynamic> ride) async {
    final pickup = _snapshotFromRidePoint(
      (ride['pickup'] as Map?)?.cast<String, dynamic>(),
    );
    final dropoff = _snapshotFromRidePoint(
      (ride['dropoff'] as Map?)?.cast<String, dynamic>(),
    );
    final fare =
        tryParseLocalizedInt(ride['agreedFareIqd']) ??
        tryParseLocalizedInt(ride['fareAfterDiscountIqd']) ??
        tryParseLocalizedInt(ride['proposedFareIqd']);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPage(
          initialPickupSnapshot: pickup,
          initialDropoffSnapshot: dropoff,
          initialFareIqd: fare,
        ),
      ),
    );
  }

  Future<void> _rebookNow(Map<String, dynamic> ride) async {
    final rideId = tryParseLocalizedInt(ride['id']);
    if (rideId == null || _rebooking) return;
    setState(() => _rebooking = true);
    try {
      await _taxiApi(ref).rebookRide(rideId);
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MapPage()));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyErrorL10n(
              error,
              fallbackBuilder: (_) => 'تعذر إعادة الحجز الآن.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _rebooking = false);
    }
  }

  String _rideStatusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'completed':
        return 'مكتملة';
      case 'cancelled':
        return 'ملغية';
      case 'expired':
        return 'انتهت';
      default:
        return status?.trim().isNotEmpty == true ? status!.trim() : 'غير معروف';
    }
  }

  Color _rideStatusColor(BuildContext context, String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'completed':
        return Colors.tealAccent.shade200;
      case 'cancelled':
        return Theme.of(context).colorScheme.error;
      default:
        return context.maslakiTokens.primaryAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorCard(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        children: [
          if (_items.isEmpty)
            const MaslakiEmptyState(
              icon: Icons.history_rounded,
              title: 'لا توجد رحلات سابقة بعد',
              body:
                  'ستظهر هنا آخر المشاوير المكتملة أو الملغاة لتعيد استخدامها أو إعادة حجزها بسرعة.',
            ),
          for (final item in _items) ...[
            MaslakiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      MaslakiStatusPill(
                        label: _rideStatusLabel(item['status']?.toString()),
                        color: _rideStatusColor(
                          context,
                          item['status']?.toString(),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'من ${(item['pickup'] as Map?)?['label'] ?? '-'}',
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  Text(
                    'إلى ${(item['dropoff'] as Map?)?['label'] ?? '-'}',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  Text(
                    'الأجرة: ${formatIqd(tryParseLocalizedInt(item['agreedFareIqd']) ?? tryParseLocalizedInt(item['fareAfterDiscountIqd']) ?? tryParseLocalizedInt(item['proposedFareIqd']) ?? 0)}',
                    textDirection: TextDirection.rtl,
                  ),
                  if ('${item['completedAt'] ?? item['cancelledAt'] ?? item['createdAt'] ?? ''}'
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${item['completedAt'] ?? item['cancelledAt'] ?? item['createdAt']}',
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: MaslakiSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: MaslakiOutlineButton(
                          onPressed: () => _reuseRoute(item),
                          icon: Icons.map_outlined,
                          label: 'استخدام نفس المسار',
                        ),
                      ),
                      const SizedBox(width: MaslakiSpacing.sm),
                      Expanded(
                        child: MaslakiPrimaryButton(
                          onPressed: _rebooking ? null : () => _rebookNow(item),
                          icon: Icons.refresh_rounded,
                          label: _rebooking ? 'جاري التنفيذ...' : 'إعادة الحجز الآن',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _MyCouponsTab extends ConsumerStatefulWidget {
  const _MyCouponsTab();

  @override
  ConsumerState<_MyCouponsTab> createState() => _MyCouponsTabState();
}

class _MyCouponsTabState extends ConsumerState<_MyCouponsTab> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _fareCtrl = TextEditingController();

  bool _loading = true;
  bool _previewing = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  _CouponPreviewState? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _fareCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _taxiApi(ref).listMyCoupons();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.taxiMyCouponsLoadFailed,
        );
      });
    }
  }

  String _couponCodeFromError(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final map = Map<String, dynamic>.from(error.response!.data as Map);
      final message = map['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return 'UNKNOWN';
  }

  String _discountTextForCoupon(Map<String, dynamic> item) {
    final type = '${item['nextDiscountType'] ?? ''}'.trim().toLowerCase();
    final value = tryParseLocalizedInt(item['nextDiscountValue']) ?? 0;
    if (value <= 0) return 'سيتم احتساب الخصم عند الاستخدام';
    if (type == 'percent') {
      return 'الخصم القادم: $value%';
    }
    return 'الخصم القادم: ${formatIqd(value)}';
  }

  _CouponPreviewState _previewFromCouponItem(Map<String, dynamic> item) {
    final code = '${item['statusCode'] ?? 'OK'}'.trim().toUpperCase();
    final title =
        item['title']?.toString().trim().isNotEmpty == true
        ? item['title'].toString().trim()
        : item['code']?.toString().trim().isNotEmpty == true
        ? item['code'].toString().trim()
        : 'كوبون';
    final remainingUses = tryParseLocalizedInt(item['remainingUses']) ?? 0;
    final body = switch (code) {
      'OK' =>
        '${_discountTextForCoupon(item)}\nالاستخدامات المتبقية: $remainingUses\nأدخل الأجرة فقط إذا أردت احتساب السعر النهائي قبل تطبيقه.',
      'COUPON_EXPIRED' => 'انتهت صلاحية هذا الكوبون.',
      'COUPON_NOT_STARTED' => 'هذا الكوبون غير متاح بعد.',
      'COUPON_INACTIVE' => 'هذا الكوبون غير مفعل حالياً.',
      'COUPON_NOT_TARGETED' => 'هذا الكوبون غير مخصص لحسابك الحالي.',
      'COUPON_USER_LIMIT_REACHED' => 'استنفدت عدد الاستخدامات المسموح بها لهذا الكوبون.',
      'COUPON_TOTAL_LIMIT_REACHED' => 'تم استنفاد هذا الكوبون بالكامل.',
      'COUPON_NO_TIERS' => 'لا توجد شرائح خصم صالحة لهذا الكوبون حالياً.',
      _ => 'تعذر معاينة هذا الكوبون حالياً.',
    };
    return _CouponPreviewState(
      statusCode: code,
      title: title,
      body: body,
      originalFareIqd: null,
      discountIqd: null,
      finalFareIqd: null,
    );
  }

  _CouponPreviewState _previewFromSuccess(Map<String, dynamic> preview) {
    final coupon =
        (preview['coupon'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final title =
        coupon['title']?.toString().trim().isNotEmpty == true
        ? coupon['title'].toString().trim()
        : coupon['code']?.toString().trim().isNotEmpty == true
        ? coupon['code'].toString().trim()
        : 'كوبون';
    return _CouponPreviewState(
      statusCode: 'OK',
      title: title,
      body: 'تم احتساب الخصم بنجاح لهذه الأجرة.',
      originalFareIqd: tryParseLocalizedInt(preview['fareBeforeDiscountIqd']),
      discountIqd: tryParseLocalizedInt(preview['discountIqd']),
      finalFareIqd: tryParseLocalizedInt(preview['fareAfterDiscountIqd']),
    );
  }

  _CouponPreviewState _previewFromFailure(String code) {
    final normalized = code.trim().toUpperCase();
    final body = switch (normalized) {
      'COUPON_NOT_FOUND' => 'الكوبون غير موجود.',
      'COUPON_INACTIVE' => 'هذا الكوبون غير مفعل حالياً.',
      'COUPON_NOT_STARTED' => 'هذا الكوبون غير متاح بعد.',
      'COUPON_EXPIRED' => 'انتهت صلاحية هذا الكوبون.',
      'COUPON_NOT_TARGETED' => 'هذا الكوبون غير مخصص لحسابك الحالي.',
      'COUPON_NO_TIERS' => 'لا توجد شرائح خصم متاحة لهذا الكوبون.',
      'COUPON_USER_LIMIT_REACHED' =>
        'وصلت إلى الحد الأقصى لاستخدام هذا الكوبون.',
      'COUPON_TOTAL_LIMIT_REACHED' => 'تم استنفاد هذا الكوبون بالكامل.',
      _ => 'تعذر معاينة الكوبون الآن. حاول مرة أخرى.',
    };
    return _CouponPreviewState(
      statusCode: normalized,
      title: 'حالة الكوبون',
      body: body,
      originalFareIqd: null,
      discountIqd: null,
      finalFareIqd: null,
    );
  }

  Future<void> _previewSelectedCoupon(Map<String, dynamic> item) async {
    _codeCtrl.text = item['code']?.toString() ?? '';
    setState(() {
      _preview = _previewFromCouponItem(item);
    });

    final fare = tryParseLocalizedInt(_fareCtrl.text.trim());
    if (fare != null && fare > 0) {
      await _previewCoupon(useSelectedItemFallback: false);
    }
  }

  Future<void> _previewCoupon({bool useSelectedItemFallback = true}) async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز الكوبون أولاً.')),
      );
      return;
    }

    final fare = tryParseLocalizedInt(_fareCtrl.text.trim());
    if (fare == null || fare <= 0) {
      if (useSelectedItemFallback) {
        final matched = _items.where((item) {
          return '${item['code'] ?? ''}'.trim().toUpperCase() == code;
        }).toList();
        if (matched.isNotEmpty) {
          setState(() {
            _preview = _previewFromCouponItem(matched.first);
          });
          return;
        }
      }
      setState(() {
        _preview = _CouponPreviewState(
          statusCode: 'FARE_CONTEXT_REQUIRED',
          title: 'معاينة الخصم',
          body:
              'يمكنك الاطلاع على نوع الخصم من الكوبون نفسه. أدخل الأجرة فقط إذا أردت حساب السعر النهائي قبل التطبيق.',
          originalFareIqd: null,
          discountIqd: null,
          finalFareIqd: null,
        );
      });
      return;
    }

    setState(() => _previewing = true);
    try {
      final preview = await _taxiApi(ref).previewCoupon(
        couponCode: code,
        proposedFareIqd: fare,
      );
      if (!mounted) return;
      setState(() {
        _preview = _previewFromSuccess(preview);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = _previewFromFailure(_couponCodeFromError(error));
      });
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorCard(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        children: [
          MaslakiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'معاينة الكوبون',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.md),
                TextField(
                  controller: _codeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.taxiCouponCodeField,
                    hintText: l10n.taxiCouponCodeHint,
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.sm),
                TextField(
                  controller: _fareCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الأجرة للحساب النهائي',
                    hintText: 'اختياري',
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.sm),
                Text(
                  'اكتب الأجرة فقط إذا أردت حساب الخصم النهائي. بدون أجرة سنعرض لك نوع الخصم وحالة الكوبون فقط.',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: MaslakiSpacing.md),
                MaslakiPrimaryButton(
                  onPressed: _previewing ? null : _previewCoupon,
                  icon: _previewing ? null : Icons.local_offer_outlined,
                  label: _previewing
                      ? 'جاري المعاينة...'
                      : l10n.taxiCouponPreviewAction,
                ),
              ],
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: MaslakiSpacing.md),
            _CouponPreviewCard(preview: _preview!),
          ],
          const SizedBox(height: MaslakiSpacing.lg),
          Text(
            l10n.taxiMyCouponsTitle,
            textDirection: TextDirection.rtl,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          if (_items.isEmpty)
            MaslakiEmptyState(
              icon: Icons.local_offer_outlined,
              title: 'لا توجد كوبونات حالياً',
              body:
                  'عندما تصبح لديك كوبونات تكسي فعالة ستظهر هنا مع حالة كل كوبون وطريقة استخدامه.',
            ),
          for (final item in _items) ...[
            InkWell(
              borderRadius: BorderRadius.circular(context.maslakiShell.cardRadius),
              onTap: () => _previewSelectedCoupon(item),
              child: MaslakiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        MaslakiStatusPill(
                          label: '${item['remainingUses'] ?? 0} استخدامات',
                        ),
                        const Spacer(),
                        Text(
                          item['title']?.toString() ??
                              item['code']?.toString() ??
                              '-',
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MaslakiSpacing.sm),
                    Text(
                      'الكود: ${item['code'] ?? '-'}',
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _discountTextForCoupon(item),
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MaslakiSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CouponPreviewState {
  final String statusCode;
  final String title;
  final String body;
  final int? originalFareIqd;
  final int? discountIqd;
  final int? finalFareIqd;

  const _CouponPreviewState({
    required this.statusCode,
    required this.title,
    required this.body,
    required this.originalFareIqd,
    required this.discountIqd,
    required this.finalFareIqd,
  });

  bool get isSuccess => statusCode == 'OK';
}

class _CouponPreviewCard extends StatelessWidget {
  final _CouponPreviewState preview;

  const _CouponPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final color = preview.isSuccess
        ? Colors.tealAccent.shade200
        : context.maslakiTokens.primaryAccent;
    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              MaslakiStatusPill(
                label: preview.isSuccess ? 'جاهز للاستخدام' : 'معلومة',
                color: color,
              ),
              const Spacer(),
              Text(
                preview.title,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          Text(
            preview.body,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (preview.isSuccess) ...[
            const SizedBox(height: MaslakiSpacing.md),
            Text(
              'الأجرة الأصلية: ${formatIqd(preview.originalFareIqd ?? 0)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Text(
              'قيمة الخصم: ${formatIqd(preview.discountIqd ?? 0)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Text(
              'الأجرة بعد الخصم: ${formatIqd(preview.finalFareIqd ?? 0)}',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedPlaceEditorScreen extends StatefulWidget {
  const _SavedPlaceEditorScreen();

  @override
  State<_SavedPlaceEditorScreen> createState() => _SavedPlaceEditorScreenState();
}

class _SavedPlaceEditorScreenState extends State<_SavedPlaceEditorScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _labelCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _reverseDebounce;

  LatLng _center = _defaultPickerCenter;
  bool _loadingSearch = false;
  bool _loadingAddress = false;
  bool _submitting = false;
  String _placeType = 'custom';
  String? _addressText;
  String? _error;
  List<_PlaceSearchResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goToCurrentLocation();
      _reverseGeocode(_center, seedLabelIfEmpty: true);
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      final nextCenter = LatLng(position.latitude, position.longitude);
      setState(() => _center = nextCenter);
      _mapController.move(nextCenter, 16.4);
      await _reverseGeocode(nextCenter, seedLabelIfEmpty: true);
    } catch (_) {
      // Keep the default center if location lookup fails.
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchPlaces(value.trim());
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _searchResults = const [];
      });
      return;
    }
    setState(() {
      _loadingSearch = true;
      _error = null;
    });
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: const {
            'User-Agent': 'MaslakiTaxi/1.0',
            'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
          },
        ),
      ).get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'format': 'jsonv2',
          'addressdetails': 1,
          'bounded': 1,
          'countrycodes': 'iq',
          'viewbox': '44.62,33.48,44.15,33.10',
          'limit': 8,
          'q': query,
        },
      );
      final raw = response.data is List ? response.data as List : const [];
      final items = raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map(_PlaceSearchResult.fromNominatim)
          .whereType<_PlaceSearchResult>()
          .toList(growable: false);
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _searchResults = items;
        _loadingSearch = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _error = 'تعذر البحث عن المكان حالياً.';
      });
    }
  }

  Future<void> _reverseGeocode(
    LatLng point, {
    bool seedLabelIfEmpty = false,
  }) async {
    setState(() => _loadingAddress = true);
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: const {
            'User-Agent': 'MaslakiTaxi/1.0',
            'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
          },
        ),
      ).get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': point.latitude,
          'lon': point.longitude,
          'zoom': 18,
          'addressdetails': 1,
        },
      );
      final data = response.data;
      if (data is! Map || !mounted) return;
      final rawAddress = '${data['display_name'] ?? ''}'.trim();
      if (rawAddress.isEmpty) return;
      final short = _shortPlaceLabel(rawAddress);
      setState(() {
        _addressText = rawAddress;
        if (seedLabelIfEmpty && _labelCtrl.text.trim().isEmpty) {
          _labelCtrl.text = short;
        }
      });
    } catch (_) {
      // Keep manual label entry if reverse geocoding fails.
    } finally {
      if (mounted) {
        setState(() => _loadingAddress = false);
      }
    }
  }

  String _shortPlaceLabel(String input) {
    final parts = input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return input;
    if (parts.length == 1) return parts.first;
    return '${parts[0]} - ${parts[1]}';
  }

  void _onSearchResultTap(_PlaceSearchResult result) {
    setState(() {
      _center = result.point;
      _addressText = result.address;
      _labelCtrl.text = result.title;
      _searchResults = const [];
      _searchCtrl.text = result.address;
    });
    _mapController.move(result.point, 16.8);
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _center = camera.center;
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 450), () {
      _reverseGeocode(camera.center, seedLabelIfEmpty: false);
    });
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final address = (_addressText ?? '').trim();
    if (label.isEmpty || address.isEmpty) {
      setState(() => _error = context.l10n.validationReviewRequiredFields);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Navigator.of(context).pop(
      _SavedPlaceDraft(
        label: label,
        placeType: _placeType,
        addressText: address,
        latitude: _center.latitude,
        longitude: _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.maslakiTokens;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taxiSavedPlaceCreateTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MaslakiSpacing.md),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    labelText: 'ابحث عن مكان',
                    hintText: 'ابحث ثم اختر من النتائج أو حرك الخريطة',
                    suffixIcon: _loadingSearch
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: MaslakiSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: MaslakiCard(
                      padding: EdgeInsets.zero,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: tokens.borderSubtle,
                        ),
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(item.title),
                            subtitle: Text(
                              item.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onSearchResultTap(item),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15.4,
                    onPositionChanged: _onMapMoved,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      fallbackUrl:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'app.maslaki.user',
                    ),
                  ],
                ),
                IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 44,
                          color: Color(0xFFD4AF37),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD4AF37),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'saved_place_current_location',
                    onPressed: _goToCurrentLocation,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: MaslakiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            if (_loadingAddress)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            const Spacer(),
                            Text(
                              'الموقع المحدد',
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: MaslakiSpacing.sm),
                        Text(
                          (_addressText ?? 'حرك الخريطة أو اختر نتيجة بحث لتحديد الموقع').trim(),
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: MaslakiSpacing.md),
                        TextField(
                          controller: _labelCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.taxiSavedPlaceLabelField,
                          ),
                        ),
                        const SizedBox(height: MaslakiSpacing.sm),
                        DropdownButtonFormField<String>(
                          initialValue: _placeType,
                          decoration: InputDecoration(
                            labelText: l10n.taxiSavedPlaceTypeLabel,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'home',
                              child: Text(l10n.taxiSavedPlaceTypeHome),
                            ),
                            DropdownMenuItem(
                              value: 'work',
                              child: Text(l10n.taxiSavedPlaceTypeWork),
                            ),
                            DropdownMenuItem(
                              value: 'custom',
                              child: Text(l10n.taxiSavedPlaceTypeCustom),
                            ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (value) {
                                  setState(() {
                                    _placeType = value ?? 'custom';
                                  });
                                },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: MaslakiSpacing.sm),
                          Text(
                            _error!,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: MaslakiSpacing.md),
                        MaslakiPrimaryButton(
                          onPressed: _submitting ? null : _save,
                          icon: Icons.check_circle_outline_rounded,
                          label: l10n.commonSave,
                        ),
                      ],
                    ),
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

class _PlaceSearchResult {
  final LatLng point;
  final String title;
  final String address;

  const _PlaceSearchResult({
    required this.point,
    required this.title,
    required this.address,
  });

  static _PlaceSearchResult? fromNominatim(Map<String, dynamic> item) {
    final lat = double.tryParse('${item['lat'] ?? ''}');
    final lng = double.tryParse('${item['lon'] ?? ''}');
    final address = '${item['display_name'] ?? ''}'.trim();
    if (lat == null || lng == null || address.isEmpty) return null;
    final parts = address
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final title = parts.isEmpty
        ? address
        : (parts.length == 1 ? parts.first : '${parts[0]} - ${parts[1]}');
    return _PlaceSearchResult(
      point: LatLng(lat, lng),
      title: title,
      address: address,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
