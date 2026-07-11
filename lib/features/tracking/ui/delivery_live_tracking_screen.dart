import 'dart:async';

import 'package:dio/dio.dart';
import 'package:maslaki/core/constants/api.dart';
import 'package:maslaki/core/i18n/locale_text.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/order_status.dart';
import '../../../core/network/session_invalidation.dart';
import '../../orders/data/orders_api.dart';
import '../../orders/models/order_item_presentation_model.dart';
import '../../orders/state/orders_controller.dart';
import '../../orders/ui/order_chat_screen.dart';
import '../../orders/ui/widgets/order_item_widgets.dart';
import '../tracking_map_utils.dart';
import 'live_tracking_shell.dart';

class DeliveryLiveTrackingScreen extends ConsumerStatefulWidget {
  final int? orderId;
  final String? publicToken;

  const DeliveryLiveTrackingScreen({super.key, this.orderId, this.publicToken})
    : assert(orderId != null || publicToken != null);

  @override
  ConsumerState<DeliveryLiveTrackingScreen> createState() =>
      _DeliveryLiveTrackingScreenState();
}

class _DeliveryLiveTrackingScreenState
    extends ConsumerState<DeliveryLiveTrackingScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  StreamSubscription<OrderTrackingLiveEvent>? _liveSub;
  StreamSubscription<OrderTrackingLiveEvent>? _publicSub;
  int? _lastTrackingEventId;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _lifecycleResumed = true;
  late final VoidCallback _sessionInvalidationListener;

  bool get _isPublic => widget.publicToken != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionInvalidationListener = _handleSessionInvalidation;
    SessionInvalidationBus.instance.addListener(_sessionInvalidationListener);
    unawaited(_load());
    _startLiveUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SessionInvalidationBus.instance.removeListener(_sessionInvalidationListener);
    _stopLiveUpdates();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleResumed = state == AppLifecycleState.resumed;
    if (_lifecycleResumed) {
      if (orderTrackingIsActive(_snapshot)) {
        unawaited(_load(silent: true));
        _startLiveUpdates();
      }
    } else {
      _stopLiveUpdates();
    }
  }

  void _handleSessionInvalidation() {
    if (!mounted) return;
    _stopLiveUpdates();
    setState(() {
      _snapshot = null;
      _loading = false;
      _error = null;
    });
  }

  void _startLiveUpdates() {
    if (!_lifecycleResumed || !orderTrackingIsActive(_snapshot)) return;
    _reconnectTimer?.cancel();
    if (_isPublic) {
      _connectPublicStream();
    } else {
      _connectTrackingStream();
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _isPublic ? 12 : 6), (_) {
      if (_lifecycleResumed && orderTrackingIsActive(_snapshot)) {
        unawaited(_load(silent: true));
      }
    });
  }

  void _stopLiveUpdates() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _liveSub?.cancel();
    _liveSub = null;
    _publicSub?.cancel();
    _publicSub = null;
  }

  void _scheduleReconnect() {
    if (!_lifecycleResumed || !orderTrackingIsActive(_snapshot)) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final seconds = <int>[2, 4, 8, 12, 20, 30][_reconnectAttempt - 1];
    _reconnectTimer = Timer(Duration(seconds: seconds), _startLiveUpdates);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
      if (!orderTrackingIsActive(_snapshot)) _stopLiveUpdates();
    }

    try {
      final api = ref.read(ordersApiProvider);
      // Hard timeout so a slow/unresponsive snapshot can never leave the screen
      // stuck on an endless loading spinner — it falls through to the error
      // state (with retry) instead.
      final data =
          await (_isPublic
                  ? api.getPublicTrackingByToken(widget.publicToken!)
                  : api.getTrackingSnapshot(widget.orderId!))
              .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _snapshot = trackingMap(data) ?? const <String, dynamic>{};
        _loading = false;
        _error = null;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      // A real 403 means this viewer is not allowed to track the order (e.g. a
      // courier who is not assigned to it). The assigned courier, the order's
      // customer, the merchant owner and admins are all authorized server-side,
      // so they will never reach this branch.
      final forbidden = error.response?.statusCode == 403;
      setState(() {
        _loading = false;
        _error = forbidden
            ? context.lt(
                ar: 'لا تملك صلاحية تتبع هذا الطلب.',
                en: 'You do not have permission to track this order.',
              )
            : context.lt(
                ar: 'تعذر تحميل التتبع الحي لهذا الطلب.',
                en: 'Failed to load live tracking for this order.',
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل التتبع الحي لهذا الطلب.',
          en: 'Failed to load live tracking for this order.',
        );
      });
    }
  }

  void _connectTrackingStream() {
    _liveSub?.cancel();
    _liveSub = ref
        .read(ordersApiProvider)
        .streamTrackingEvents(
          orderId: widget.orderId!,
          lastEventId: _lastTrackingEventId,
        )
        .listen(
          (event) {
            if (!mounted) return;
            _reconnectAttempt = 0;
            if (event.eventId != null) {
              _lastTrackingEventId = event.eventId;
            }
            if (event.event == 'order_tracking_update') {
              setState(() {
                _snapshot = mergeOrderTrackingEvent(_snapshot, event.data);
                _loading = false;
                _error = null;
              });
              if (!orderTrackingIsActive(_snapshot)) _stopLiveUpdates();
            } else if (event.event == 'notification' ||
                event.event == 'resync_required') {
              unawaited(_load(silent: true));
            }
          },
          onError: (error, stack) {
            unawaited(_load(silent: true));
            _scheduleReconnect();
          },
          onDone: _scheduleReconnect,
        );
  }

  void _connectPublicStream() {
    _publicSub?.cancel();
    _publicSub = ref
        .read(ordersApiProvider)
        .streamPublicTrackingByToken(widget.publicToken!)
        .listen(
          (event) {
            if (!mounted) return;
            _reconnectAttempt = 0;
            if (event.event == 'order_tracking_update') {
              setState(() {
                _snapshot = mergeOrderTrackingEvent(_snapshot, event.data);
                _error = null;
                _loading = false;
              });
              if (!orderTrackingIsActive(_snapshot)) _stopLiveUpdates();
              return;
            }
            if (event.event == 'resync_required' || event.event == 'closed') {
              unawaited(_load(silent: true));
            }
          },
          onError: (error, stack) {
            unawaited(_load(silent: true));
            _scheduleReconnect();
          },
          onDone: _scheduleReconnect,
        );
  }

  Future<void> _shareTracking() async {
    if (_isPublic || widget.orderId == null) return;
    final shareTextPrefix = context.lt(
      ar: 'تتبع طلبي في مسلكي:',
      en: 'Track my Maslaki order:',
    );
    try {
      final out = await ref
          .read(ordersApiProvider)
          .createTrackingShareToken(widget.orderId!);
      final token = (out['token'] ?? '').toString().trim();
      if (token.isEmpty) return;
      final url = '${Api.baseUrl}/api/orders/public/track/$token';
      await SharePlus.instance.share(
        ShareParams(text: '$shareTextPrefix\n$url'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر إنشاء رابط المشاركة الآن.',
              en: 'Failed to create a share link right now.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _callCourier() async {
    final phone = _string(_courier?['phone']);
    if (phone == null || phone.isEmpty) return;
    await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openChat() async {
    if (_isPublic || widget.orderId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderChatScreen(orderId: widget.orderId!),
      ),
    );
  }

  Map<String, dynamic>? get _order {
    return trackingMap(_snapshot?['order']);
  }

  List<OrderItemPresentationModel> get _presentationItems {
    final order = _order;
    if (order == null) return const [];
    final rawItems = order['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map(
          (entry) => OrderItemPresentationModel.fromRawMap(
            Map<String, dynamic>.from(entry),
            orderContext: order,
          ),
        )
        .toList(growable: false);
  }

  Map<String, dynamic>? get _courier {
    return trackingMap(_snapshot?['courier']);
  }

  Map<String, dynamic>? get _latestLocation {
    return trackingMap(_snapshot?['latestLocation']);
  }

  Map<String, dynamic>? get _destination {
    return trackingMap(_snapshot?['destination']);
  }

  LatLng? get _destinationPoint {
    final explicit = latLngFromMap(_destination);
    if (explicit != null) return explicit;
    final block =
        _string(_destination?['block']) ??
        _string(_order?['customerBlock']) ??
        '';
    final building =
        _string(_destination?['buildingNumber']) ??
        _string(_order?['customerBuildingNumber']) ??
        '';
    if (block.isEmpty || building.isEmpty) return null;
    return approximateBasmayaAddressPoint(
      block: block,
      buildingNumber: building,
    );
  }

  LatLng get _initialCenter =>
      latLngFromMap(_latestLocation) ??
      _destinationPoint ??
      basmayaTrackingCenter;

  List<Marker> get _markers {
    final tokens = context.maslakiTokens;
    final items = <Marker>[];
    final destination = _destinationPoint;
    final courierPoint = latLngFromMap(_latestLocation);

    if (destination != null) {
      items.add(
        Marker(
          point: destination,
          width: 50,
          height: 50,
          child: Icon(
            Icons.location_on_rounded,
            color: tokens.primaryAccent,
            size: 40,
          ),
        ),
      );
    }

    if (courierPoint != null) {
      items.add(
        Marker(
          point: courierPoint,
          width: 58,
          height: 58,
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surfaceSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.primaryAccent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tokens.glowPrimary.withValues(alpha: 0.34),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.two_wheeler_rounded,
              color: tokens.primaryAccent,
              size: 30,
            ),
          ),
        ),
      );
    }

    return items;
  }

  List<Polyline> get _polylines {
    final courierPoint = latLngFromMap(_latestLocation);
    final destination = _destinationPoint;
    if (courierPoint == null || destination == null) return const [];
    return [
      Polyline(
        points: [courierPoint, destination],
        strokeWidth: 4.2,
        color: context.maslakiTokens.primaryAccent.withValues(alpha: 0.9),
      ),
    ];
  }

  String get _destinationLabel {
    final label = _string(_destination?['label']);
    if (label != null && label.isNotEmpty) return label;
    final city =
        _string(_destination?['city']) ??
        _string(_order?['customerCity']) ??
        '-';
    final block =
        _string(_destination?['block']) ??
        _string(_order?['customerBlock']) ??
        '-';
    final building =
        _string(_destination?['buildingNumber']) ??
        _string(_order?['customerBuildingNumber']) ??
        '-';
    return '$city - $block - $building';
  }

  List<_DeliveryTimelineEntry> get _timelineEntries {
    final order = _order;
    if (order == null) return const [];
    return [
      _DeliveryTimelineEntry(
        labelAr: 'تم إنشاء الطلب',
        labelEn: 'Order placed',
        time: _date(order['createdAt']),
      ),
      _DeliveryTimelineEntry(
        labelAr: 'تم قبول الطلب',
        labelEn: 'Order accepted',
        time: _date(order['approvedAt']),
      ),
      _DeliveryTimelineEntry(
        labelAr: 'جارٍ التحضير',
        labelEn: 'Being prepared',
        time: _date(order['preparingStartedAt']) ?? _date(order['preparedAt']),
      ),
      _DeliveryTimelineEntry(
        labelAr: 'تم الاستلام من المتجر',
        labelEn: 'Picked up',
        time: _date(order['pickedUpAt']),
      ),
      _DeliveryTimelineEntry(
        labelAr: 'بالقرب من العنوان',
        labelEn: 'Near customer',
        time: _date(order['arrivedAt']),
      ),
      _DeliveryTimelineEntry(
        labelAr: 'تم التسليم',
        labelEn: 'Delivered',
        time:
            _date(order['deliveredAt']) ?? _date(order['customerConfirmedAt']),
      ),
    ];
  }

  String _stageLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'order_accepted':
        return context.lt(ar: 'تم قبول الطلب', en: 'Order accepted');
      case 'being_prepared':
        return context.lt(ar: 'جارٍ التحضير', en: 'Being prepared');
      case 'ready_for_pickup':
        return context.lt(ar: 'جاهز للاستلام', en: 'Ready for pickup');
      case 'heading_to_customer':
        return context.lt(ar: 'في الطريق إليك', en: 'Heading to you');
      case 'near_customer':
        return context.lt(ar: 'قريب منك الآن', en: 'Near customer');
      case 'delivered':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      case 'cancelled':
        return context.lt(ar: 'تم إلغاء الطلب', en: 'Order cancelled');
      default:
        return context.lt(ar: 'تم إنشاء الطلب', en: 'Order placed');
    }
  }

  String _courierStatusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'approved':
      case 'preparing':
      case 'ready_for_delivery':
        return context.lt(ar: 'بانتظار الاستلام', en: 'Awaiting pickup');
      case 'picked_up':
      case 'on_the_way':
        return context.lt(ar: 'في الطريق', en: 'On the way');
      case 'arrived':
        return context.lt(ar: 'وصل', en: 'Arrived');
      case 'delivered':
      case 'completed':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      default:
        return context.lt(ar: 'بانتظار التعيين', en: 'Awaiting assignment');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.maslakiTokens.backgroundPrimary,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _snapshot == null || _order == null) {
      final tokens = context.maslakiTokens;
      return Scaffold(
        backgroundColor: tokens.backgroundPrimary,
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_off_rounded,
                  size: 40,
                  color: tokens.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  (_error ?? '').isEmpty
                      ? context.lt(
                          ar: 'تعذر تحميل التتبع الحي لهذا الطلب.',
                          en: 'Failed to load live tracking for this order.',
                        )
                      : _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => unawaited(_load()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.lt(ar: 'إعادة المحاولة', en: 'Retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tokens = context.maslakiTokens;
    final order = _order!;
    final items = _presentationItems;
    final groupByStore = items
            .map((item) => '${item.storeId ?? item.storeName ?? 'store'}')
            .toSet()
            .length >
        1;
    final topActions = <Widget>[
      if (!_isPublic)
        _TrackingActionButton(
          icon: Icons.share_outlined,
          tooltip: context.lt(ar: 'مشاركة', en: 'Share'),
          onPressed: _shareTracking,
        ),
      if (!_isPublic && (_courier?['phone'] ?? '').toString().trim().isNotEmpty)
        _TrackingActionButton(
          icon: Icons.call_outlined,
          tooltip: context.lt(ar: 'اتصال', en: 'Call'),
          onPressed: _callCourier,
        ),
      if (!_isPublic)
        _TrackingActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          tooltip: context.lt(ar: 'محادثة', en: 'Chat'),
          onPressed: _openChat,
        ),
    ];

    return LiveTrackingShell(
      title: context.lt(ar: 'تتبع الطلب الحي', en: 'Live Order Tracking'),
      initialCenter: _initialCenter,
      markers: _markers,
      polylines: _polylines,
      topActions: topActions,
      sheetBuilder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              '#${_readInt(order['id']) ?? widget.orderId ?? 0}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _DeliveryStatusBadge(
              label: _stageLabel(_string(_snapshot?['stage']) ?? ''),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  for (final item in items.take(3))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: OrderItemThumbnail(
                        imageUrl: item.displayImageUrl,
                        activityType: item.activityType,
                        size: 52,
                      ),
                    ),
                  if (items.length > 3)
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        '+${items.length - 3}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OrderItemsSummaryList(
                items: items,
                compact: true,
                groupByStore: groupByStore,
              ),
            ],
            const SizedBox(height: 16),
            _DeliveryInfoTile(
              title: context.lt(ar: 'حالة الطلب', en: 'Order status'),
              value: orderStatusLabel(_string(order['status']) ?? ''),
            ),
            _DeliveryInfoTile(
              title: context.lt(ar: 'حالة السائق', en: 'Courier status'),
              value: _courierStatusLabel(_string(order['status'])),
            ),
            _DeliveryInfoTile(
              title: context.lt(ar: 'المتجر', en: 'Merchant'),
              value:
                  _string(order['merchantName']) ??
                  trackingNestedString(_snapshot?['merchant'], const [
                    'name',
                  ]) ??
                  '-',
            ),
            _DeliveryInfoTile(
              title: context.lt(ar: 'المندوب', en: 'Courier'),
              value:
                  _string(_courier?['fullName']) ??
                  context.lt(ar: 'بانتظار التعيين', en: 'Awaiting assignment'),
            ),
            _DeliveryInfoTile(
              title: context.lt(ar: 'الوجهة', en: 'Destination'),
              value: _destinationLabel,
            ),
            _DeliveryInfoTile(
              title: context.lt(ar: 'الإجمالي', en: 'Total'),
              value:
                  '${_readNum(order['totalAmount']) ?? _readNum(order['total_amount']) ?? 0} د.ع',
            ),
            if (_latestLocation != null)
              _DeliveryInfoTile(
                title: context.lt(ar: 'آخر تحديث', en: 'Last update'),
                value:
                    _string(_latestLocation?['updatedAt']) ??
                    _string(_snapshot?['lastUpdatedAt']) ??
                    '-',
              ),
            const SizedBox(height: 18),
            Text(
              context.lt(ar: 'التسلسل الزمني', en: 'Timeline'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ..._timelineEntries.map(_DeliveryTimelineRow.new),
          ],
        );
      },
    );
  }

  DateTime? _date(dynamic value) {
    final raw = _string(value);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String? _string(dynamic value) {
    return trackingString(value);
  }

  int? _readInt(dynamic value) => int.tryParse('${value ?? ''}');

  double? _readNum(dynamic value) => double.tryParse('${value ?? ''}');
}

class _TrackingActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TrackingActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.surfaceSecondary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Icon(icon, color: tokens.primaryAccent, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryStatusBadge extends StatelessWidget {
  final String label;

  const _DeliveryStatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.primaryAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.primaryAccent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: tokens.primaryAccent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DeliveryInfoTile extends StatelessWidget {
  final String title;
  final String value;

  const _DeliveryInfoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryTimelineEntry {
  final String labelAr;
  final String labelEn;
  final DateTime? time;

  const _DeliveryTimelineEntry({
    required this.labelAr,
    required this.labelEn,
    required this.time,
  });
}

class _DeliveryTimelineRow extends StatelessWidget {
  final _DeliveryTimelineEntry entry;

  const _DeliveryTimelineRow(this.entry);

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final isDone = entry.time != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? tokens.primaryAccent
                  : tokens.textSecondary.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.lt(ar: entry.labelAr, en: entry.labelEn),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.time?.toLocal().toString() ??
                      context.lt(ar: 'قريبًا', en: 'Pending'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
