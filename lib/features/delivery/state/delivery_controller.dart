import 'dart:async';

import 'package:core_maps/core_maps.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/session_invalidation.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/models/order_model.dart';
import '../../tracking/tracking_map_utils.dart';
import '../data/delivery_api.dart';

final deliveryApiProvider = Provider<DeliveryApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return DeliveryApi(dio);
});

final deliveryControllerProvider =
    StateNotifierProvider<DeliveryController, DeliveryState>((ref) {
      return DeliveryController(ref);
    });

/// حالة تجربة المندوب: الطلبات الحالية، السجل، الطلبات المعلقة، والتحليلات.
class DeliveryState {
  final bool loading;
  final bool saving;
  final List<OrderModel> currentOrders;
  final List<OrderModel> historyOrders;
  final List<Map<String, dynamic>> pendingRequests;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic> dashboardV2;
  final Map<String, dynamic> reportsV2;
  final Map<String, dynamic> competitionsV2;
  final Map<String, dynamic> competitionsHistoryV2;
  final Map<String, dynamic> competitionProgressV2;
  final Map<String, dynamic> competitionAchievementsV2;
  final Map<String, dynamic> endDayReadiness;
  final String? error;
  final String? lastArchiveMessage;

  const DeliveryState({
    this.loading = false,
    this.saving = false,
    this.currentOrders = const [],
    this.historyOrders = const [],
    this.pendingRequests = const [],
    this.analytics = const {},
    this.dashboardV2 = const {},
    this.reportsV2 = const {},
    this.competitionsV2 = const {},
    this.competitionsHistoryV2 = const {},
    this.competitionProgressV2 = const {},
    this.competitionAchievementsV2 = const {},
    this.endDayReadiness = const {},
    this.error,
    this.lastArchiveMessage,
  });

  DeliveryState copyWith({
    bool? loading,
    bool? saving,
    List<OrderModel>? currentOrders,
    List<OrderModel>? historyOrders,
    List<Map<String, dynamic>>? pendingRequests,
    Map<String, dynamic>? analytics,
    Map<String, dynamic>? dashboardV2,
    Map<String, dynamic>? reportsV2,
    Map<String, dynamic>? competitionsV2,
    Map<String, dynamic>? competitionsHistoryV2,
    Map<String, dynamic>? competitionProgressV2,
    Map<String, dynamic>? competitionAchievementsV2,
    Map<String, dynamic>? endDayReadiness,
    String? error,
    String? lastArchiveMessage,
  }) {
    return DeliveryState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      currentOrders: currentOrders ?? this.currentOrders,
      historyOrders: historyOrders ?? this.historyOrders,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      analytics: analytics ?? this.analytics,
      dashboardV2: dashboardV2 ?? this.dashboardV2,
      reportsV2: reportsV2 ?? this.reportsV2,
      competitionsV2: competitionsV2 ?? this.competitionsV2,
      competitionsHistoryV2:
          competitionsHistoryV2 ?? this.competitionsHistoryV2,
      competitionProgressV2:
          competitionProgressV2 ?? this.competitionProgressV2,
      competitionAchievementsV2:
          competitionAchievementsV2 ?? this.competitionAchievementsV2,
      endDayReadiness: endDayReadiness ?? this.endDayReadiness,
      error: error,
      lastArchiveMessage: lastArchiveMessage ?? this.lastArchiveMessage,
    );
  }
}

/// المتحكم المركزي لتجربة الدليفري داخل Flutter.
///
/// Critical notes:
/// - source of truth لشاشات الدليفري الحالية والتاريخ والتقارير.
/// - يوقف polling تلقائياً إذا فقد المستخدم دور الدليفري.
class DeliveryController extends StateNotifier<DeliveryState>
    with WidgetsBindingObserver {
  final Ref ref;
  Timer? _liveOrdersTimer;
  DateTime? _lastPresenceSyncAt;
  bool _liveFetchInFlight = false;
  bool _presenceSyncInFlight = false;
  bool _disposed = false;
  int _livePollingSubscribers = 0;
  bool _lifecycleResumed = true;
  late final VoidCallback _sessionInvalidationListener;

  DeliveryController(this.ref) : super(const DeliveryState()) {
    WidgetsBinding.instance.addObserver(this);
    _sessionInvalidationListener = _handleSessionInvalidation;
    SessionInvalidationBus.instance.addListener(_sessionInvalidationListener);
    _lifecycleResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasResumed = _lifecycleResumed;
    _lifecycleResumed = state == AppLifecycleState.resumed;
    // Returning to the foreground must not depend on a push or the next poll
    // tick: refresh the assigned/current orders immediately so an order that
    // was assigned while the app was backgrounded shows up right away.
    if (!wasResumed && _lifecycleResumed && _canRunDeliveryPolling()) {
      unawaited(refreshCurrentOrders(silent: true));
    }
  }

  void _setStateSafely(DeliveryState nextState) {
    if (_disposed) return;
    state = nextState;
  }

  void _handleSessionInvalidation() {
    if (_disposed) return;
    stopLiveOrders(force: true);
    _liveFetchInFlight = false;
    _presenceSyncInFlight = false;
    _lastPresenceSyncAt = null;
    _setStateSafely(const DeliveryState());
  }

  bool _canRunDeliveryPolling() {
    final auth = ref.read(authControllerProvider);
    return auth.isAuthed && auth.isDelivery;
  }

  bool _isDeliveryForbiddenError(DioException error) {
    if (error.response?.statusCode != 403) return false;
    final data = error.response?.data;
    if (data is! Map) return false;
    final message = '${data['message'] ?? ''}'.trim().toUpperCase();
    final code = '${data['code'] ?? ''}'.trim().toUpperCase();
    return message == 'FORBIDDEN_DELIVERY_ONLY' ||
        code == 'FORBIDDEN_DELIVERY_ONLY';
  }

  List<OrderModel> _trackableOrders(List<OrderModel> orders) {
    return orders
        .where((order) {
          final normalized = normalizeOrderStatusForUi(order.status);
          final hasCourier = order.hasAssignedDelivery;
          return hasCourier &&
              const {
                'ready_for_delivery',
                'on_the_way',
                'arrived',
              }.contains(normalized);
        })
        .toList(growable: false);
  }

  Future<void> _publishCourierPresence({
    required DeliveryApi api,
    required Position position,
    required List<OrderModel> currentOrders,
  }) async {
    final trackable = _trackableOrders(currentOrders);
    var publishedPresence = false;
    for (final order in trackable) {
      if (!canPublishCourierLocation(
        lifecycleResumed: _lifecycleResumed,
        permissionGranted: true,
        assigned: order.hasAssignedDelivery,
        status: normalizeOrderStatusForUi(order.status),
      )) {
        continue;
      }
      await api.upsertPresence(
        orderId: order.id,
        latitude: position.latitude,
        longitude: position.longitude,
        headingDeg: position.heading.isFinite ? position.heading : null,
        speedKmh: position.speed.isFinite ? position.speed * 3.6 : null,
        accuracyM: position.accuracy.isFinite ? position.accuracy : null,
      );
      publishedPresence = true;
    }
    if (!publishedPresence) {
      await api.upsertPresence(
        latitude: position.latitude,
        longitude: position.longitude,
        headingDeg: position.heading.isFinite ? position.heading : null,
        speedKmh: position.speed.isFinite ? position.speed * 3.6 : null,
        accuracyM: position.accuracy.isFinite ? position.accuracy : null,
      );
    }
    _lastPresenceSyncAt = DateTime.now();
  }

  Future<void> _syncCourierPresence({bool force = false}) async {
    if (_disposed ||
        _presenceSyncInFlight ||
        !_lifecycleResumed ||
        !_canRunDeliveryPolling()) {
      return;
    }
    final trackable = _trackableOrders(state.currentOrders);
    if (trackable.isEmpty) return;
    if (!force && _lastPresenceSyncAt != null) {
      final elapsed = DateTime.now().difference(_lastPresenceSyncAt!);
      if (elapsed < const Duration(seconds: 18)) return;
    }

    _presenceSyncInFlight = true;
    try {
      final permissionService = ref.read(locationPermissionServiceProvider);
      final status = await permissionService.getStatus();
      if (!status.serviceEnabled) return;
      var permissionState = status.state;
      if (permissionState == AppLocationPermissionState.denied) {
        permissionState = (await permissionService.requestPermission()).state;
      }
      if (permissionState == AppLocationPermissionState.denied ||
          permissionState == AppLocationPermissionState.permanentlyDenied ||
          permissionState == AppLocationPermissionState.serviceDisabled) {
        return;
      }
      final permissionGranted =
          permissionState == AppLocationPermissionState.grantedApproximate ||
          permissionState == AppLocationPermissionState.grantedPrecise;
      if (!permissionGranted || !_lifecycleResumed) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );
      final api = ref.read(deliveryApiProvider);
      await _publishCourierPresence(
        api: api,
        position: position,
        currentOrders: state.currentOrders,
      );
    } catch (_) {
      // Best-effort live tracking update; failures must not break courier flows.
    } finally {
      _presenceSyncInFlight = false;
    }
  }

  Future<void> syncCourierPresenceForTesting({
    bool force = false,
    bool skipPreconditions = false,
    DeliveryApi? apiOverride,
    Position? positionOverride,
    List<OrderModel>? currentOrdersOverride,
  }) async {
    if (!skipPreconditions) {
      return _syncCourierPresence(force: force);
    }
    final DeliveryApi api = apiOverride ?? ref.read(deliveryApiProvider);
    final position =
        positionOverride ??
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 12),
        );
    await _publishCourierPresence(
      api: api,
      position: position,
      currentOrders: currentOrdersOverride ?? state.currentOrders,
    );
  }

  /// يحمل snapshot أولية تشمل الطلبات، analytics، dashboard، والتقارير.
  Future<void> bootstrap({String? historyDate}) async {
    _setStateSafely(state.copyWith(loading: true, error: null));
    try {
      final api = ref.read(deliveryApiProvider);
      // Capture (rather than swallow) a failure of the critical current-orders
      // fetch. If it fails we must show a real error + retry, never a
      // misleading "no items" empty state that hides an assigned order.
      Object? ordersError;
      final ordersFuture = api.ordersV2().catchError((Object e) {
        ordersError = e;
        return <dynamic>[];
      });
      final analyticsFuture = api.analytics().catchError(
        (_) => <String, dynamic>{},
      );
      final dashboardV2Future = api.dashboardV2().catchError(
        (_) => <String, dynamic>{},
      );
      final reportsV2Future = api.reportsV2().catchError(
        (_) => <String, dynamic>{},
      );
      final requestsFuture = api.requestsV2().catchError((_) => <dynamic>[]);
      final competitionsFuture = api
          .competitionsV2(scope: 'active')
          .catchError((_) => <String, dynamic>{});
      final competitionsHistoryFuture = api
          .competitionsV2(scope: 'history')
          .catchError((_) => <String, dynamic>{});
      final competitionProgressFuture = api.competitionProgressV2().catchError(
        (_) => <String, dynamic>{},
      );
      final competitionAchievementsFuture = api
          .competitionAchievementsSummaryV2()
          .catchError((_) => <String, dynamic>{});
      final endDayReadinessFuture = api.endDayReadiness().catchError(
        (_) => <String, dynamic>{
          'canEndDay': true,
          'openSettlements': <dynamic>[],
        },
      );

      await Future.wait([
        ordersFuture,
        analyticsFuture,
        dashboardV2Future,
        reportsV2Future,
        requestsFuture,
        competitionsFuture,
        competitionsHistoryFuture,
        competitionProgressFuture,
        competitionAchievementsFuture,
        endDayReadinessFuture,
      ]);

      final ordersResponse = await ordersFuture;
      final analyticsResponse = await analyticsFuture;
      final dashboardV2 = await dashboardV2Future;
      final reportsV2 = await reportsV2Future;
      final requestsRaw = await requestsFuture;
      final competitionsV2 = await competitionsFuture;
      final competitionsHistoryV2 = await competitionsHistoryFuture;
      final competitionProgressV2 = await competitionProgressFuture;
      final competitionAchievementsV2 = await competitionAchievementsFuture;
      final endDayReadiness = await endDayReadinessFuture;

      if (ordersError != null) {
        final err = ordersError;
        if (err is DioException && _isDeliveryForbiddenError(err)) {
          stopLiveOrders(force: true);
        }
        // Preserve any orders already on screen instead of blanking the list,
        // and surface an error so the UI can offer a retry.
        _setStateSafely(
          state.copyWith(
            loading: false,
            error: err is DioException
                ? _mapError(err)
                : resolveLocalizedText(
                    (l10n) => l10n.deliveryDashboardLoadFailed,
                  ),
          ),
        );
        return;
      }

      final allOrders = ordersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);

      bool isHistory(OrderModel order) {
        final normalized = normalizeOrderStatusForUi(order.status);
        return const {
          'delivered',
          'received',
          'completed',
          'cancelled',
          'failed_delivery',
          'returned_if_needed',
        }.contains(normalized);
      }

      DateTime? toDateOnly(DateTime? value) =>
          value == null ? null : DateTime(value.year, value.month, value.day);

      DateTime? requestedHistoryDay;
      if (historyDate != null && historyDate.trim().isNotEmpty) {
        requestedHistoryDay = DateTime.tryParse(historyDate.trim());
        requestedHistoryDay = toDateOnly(requestedHistoryDay);
      }

      final currentOrders = allOrders
          .where((o) => !isHistory(o))
          .toList(growable: false);
      var historyOrders = allOrders.where(isHistory).toList(growable: false);
      if (requestedHistoryDay != null) {
        historyOrders = historyOrders
            .where((o) {
              final refDate =
                  toDateOnly(o.customerConfirmedAt) ??
                  toDateOnly(o.deliveredAt) ??
                  toDateOnly(o.createdAt);
              return refDate == requestedHistoryDay;
            })
            .toList(growable: false);
      }

      _setStateSafely(
        state.copyWith(
          loading: false,
          currentOrders: currentOrders,
          historyOrders: historyOrders,
          pendingRequests: requestsRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
          analytics: analyticsResponse,
          dashboardV2: dashboardV2,
          reportsV2: reportsV2,
          competitionsV2: competitionsV2,
          competitionsHistoryV2: competitionsHistoryV2,
          competitionProgressV2: competitionProgressV2,
          competitionAchievementsV2: competitionAchievementsV2,
          endDayReadiness: Map<String, dynamic>.from(endDayReadiness),
        ),
      );
      unawaited(_syncCourierPresence());
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(loading: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          loading: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryDashboardLoadFailed,
          ),
        ),
      );
    }
  }

  Future<void> refreshCurrentOrders({bool silent = false}) async {
    try {
      final api = ref.read(deliveryApiProvider);
      final currentFuture = api.ordersV2();
      final requestsFuture = api.requestsV2().catchError((_) => <dynamic>[]);
      final dashboardFuture = api.dashboardV2().catchError(
        (_) => <String, dynamic>{},
      );
      final competitionsFuture = api
          .competitionsV2(scope: 'active')
          .catchError((_) => <String, dynamic>{'competitions': <dynamic>[]});
      final competitionsHistoryFuture = api
          .competitionsV2(scope: 'history')
          .catchError((_) => <String, dynamic>{'competitions': <dynamic>[]});
      final competitionProgressFuture = api.competitionProgressV2().catchError(
        (_) => <String, dynamic>{'items': <dynamic>[]},
      );
      final competitionAchievementsFuture = api
          .competitionAchievementsSummaryV2()
          .catchError((_) => <String, dynamic>{'summary': <String, dynamic>{}});
      final endDayReadinessFuture = api.endDayReadiness().catchError(
        (_) => <String, dynamic>{
          'canEndDay': true,
          'openSettlements': <dynamic>[],
        },
      );

      await Future.wait([
        currentFuture,
        requestsFuture,
        dashboardFuture,
        competitionsFuture,
        competitionsHistoryFuture,
        competitionProgressFuture,
        competitionAchievementsFuture,
        endDayReadinessFuture,
      ]);

      final currentResponse = await currentFuture;
      final requestsResponse = await requestsFuture;
      final dashboardV2 = await dashboardFuture;
      final competitionsV2 = await competitionsFuture;
      final competitionsHistoryV2 = await competitionsHistoryFuture;
      final competitionProgressV2 = await competitionProgressFuture;
      final competitionAchievementsV2 = await competitionAchievementsFuture;
      final endDayReadiness = await endDayReadinessFuture;

      final allOrders = currentResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      final currentOrders = allOrders
          .where((o) {
            final normalized = normalizeOrderStatusForUi(o.status);
            return !const {
              'delivered',
              'received',
              'completed',
              'cancelled',
              'failed_delivery',
              'returned_if_needed',
            }.contains(normalized);
          })
          .toList(growable: false);
      _setStateSafely(
        state.copyWith(
          currentOrders: currentOrders,
          pendingRequests: requestsResponse
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
          dashboardV2: dashboardV2,
          competitionsV2: competitionsV2,
          competitionsHistoryV2: competitionsHistoryV2,
          competitionProgressV2: competitionProgressV2,
          competitionAchievementsV2: competitionAchievementsV2,
          endDayReadiness: Map<String, dynamic>.from(endDayReadiness),
          error: null,
        ),
      );
      unawaited(_syncCourierPresence());
    } on DioException catch (e) {
      if (_isDeliveryForbiddenError(e)) {
        stopLiveOrders(force: true);
      }
      if (silent) return;
      _setStateSafely(state.copyWith(error: _mapError(e)));
    }
  }

  void startLiveOrders({Duration interval = const Duration(seconds: 6)}) {
    if (!_canRunDeliveryPolling()) {
      stopLiveOrders(force: true);
      return;
    }
    _livePollingSubscribers += 1;
    if (_liveOrdersTimer != null) return;
    _liveOrdersTimer = Timer.periodic(interval, (_) async {
      if (_disposed || _liveFetchInFlight) return;
      if (!_canRunDeliveryPolling()) {
        stopLiveOrders(force: true);
        return;
      }
      _liveFetchInFlight = true;
      try {
        await refreshCurrentOrders(silent: true);
        await _syncCourierPresence();
      } finally {
        _liveFetchInFlight = false;
      }
    });
  }

  void stopLiveOrders({bool force = false}) {
    if (force) {
      _livePollingSubscribers = 0;
    } else if (_livePollingSubscribers > 0) {
      _livePollingSubscribers -= 1;
    }
    if (_livePollingSubscribers > 0) return;
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = null;
  }

  Future<void> acceptRequest(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref.read(deliveryApiProvider).acceptOrderV2(orderId, note: note);
      await ref
          .read(localNotificationsProvider)
          .cancelDeliveryPickupReminder(orderId);
      await bootstrap();
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryAcceptRequestFailed,
          ),
        ),
      );
    }
  }

  Future<void> rejectRequest(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref.read(deliveryApiProvider).rejectOrderV2(orderId, note: note);
      await bootstrap();
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryRejectRequestFailed,
          ),
        ),
      );
    }
  }

  Future<void> pickedUpOrder(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref.read(deliveryApiProvider).pickedUpV2(orderId, note: note);
      await bootstrap();
      await _syncCourierPresence(force: true);
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryPickedUpOrderFailed,
          ),
        ),
      );
    }
  }

  Future<void> arrivedOrder(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref.read(deliveryApiProvider).arrivedV2(orderId, note: note);
      await bootstrap();
      await _syncCourierPresence(force: true);
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryArrivedOrderFailed,
          ),
        ),
      );
    }
  }

  Future<void> deliveredOrder(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref.read(deliveryApiProvider).deliveredV2(orderId, note: note);
      await bootstrap();
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryDeliveredOrderFailed,
          ),
        ),
      );
    }
  }

  Future<void> requestCancelOrder(
    int orderId, {
    required String reasonCode,
    String? reasonText,
  }) async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      await ref
          .read(deliveryApiProvider)
          .requestCancelV2(
            orderId,
            reasonCode: reasonCode,
            reasonText: reasonText,
          );
      await bootstrap();
      _setStateSafely(state.copyWith(saving: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText(
            (l10n) => l10n.deliveryCancelOrderRequestFailed,
          ),
        ),
      );
    }
  }

  // Backward compatible wrappers for existing screens:
  Future<void> claimOrder(int orderId) => pickedUpOrder(orderId);

  Future<void> startOrder(int orderId) => arrivedOrder(orderId);

  Future<void> markDelivered(int orderId) => deliveredOrder(orderId);

  Map<String, dynamic> _normalizeReadiness(Map<String, dynamic>? value) {
    return value == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(value);
  }

  String _deliveryEndDayBlockedMessage(Map<String, dynamic> readiness) {
    final outstanding =
        num.tryParse('${readiness['outstandingAmount'] ?? 0}') ?? 0;
    final appDue = num.tryParse('${readiness['totalAppDue'] ?? 0}') ?? 0;
    final differenceDue =
        num.tryParse('${readiness['totalDifferenceDue'] ?? 0}') ?? 0;
    final openSettlements = List<dynamic>.from(
      readiness['openSettlements'] as List? ?? const [],
    );
    final blockingReasonAr = '${readiness['blockingReasonAr'] ?? ''}'.trim();
    final blockingReasonEn = '${readiness['blockingReasonEn'] ?? ''}'.trim();
    final reasonText = [
      if (blockingReasonAr.isNotEmpty) blockingReasonAr,
      if (blockingReasonEn.isNotEmpty) blockingReasonEn,
    ].join(' / ');
    final amountText =
        'App due: ${formatIqd(appDue)} | Differences: ${formatIqd(differenceDue)} | Outstanding: ${formatIqd(outstanding)}';
    return openSettlements.isEmpty
        ? 'لا يمكن إنهاء اليوم / Cannot close the day yet. $reasonText. $amountText'
        : 'لا يمكن إنهاء اليوم / Cannot close the day while ${openSettlements.length} settlement(s) remain open. $reasonText. $amountText';
  }

  Future<void> endDay() async {
    _setStateSafely(state.copyWith(saving: true, error: null));
    try {
      final readiness = _normalizeReadiness(
        await ref.read(deliveryApiProvider).endDayReadiness(),
      );
      _setStateSafely(state.copyWith(endDayReadiness: readiness));
      final canEndDay = readiness['canEndDay'] == true;
      if (!canEndDay) {
        _setStateSafely(
          state.copyWith(
            saving: false,
            error: _deliveryEndDayBlockedMessage(readiness),
          ),
        );
        return;
      }

      final summary = await ref.read(deliveryApiProvider).endDay();
      final count = summary['ordersCount'] ?? 0;
      final date = summary['archiveDate'] ?? '';
      final amount = summary['totalAmount'] ?? 0;
      await bootstrap();
      _setStateSafely(
        state.copyWith(
          saving: false,
          lastArchiveMessage: resolveLocalizedText(
            (l10n) =>
                l10n.deliveryEndDaySummary(date, '$count', formatIqd(amount)),
          ),
        ),
      );
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(saving: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(
          saving: false,
          error: resolveLocalizedText((l10n) => l10n.deliveryEndDayFailed),
        ),
      );
    }
  }

  String _mapError(DioException e) {
    return mapDioErrorL10n(
      e,
      fallbackBuilder: (l10n) => l10n.commonServerConnectionFailed,
      customMessages: const {
        'DELIVERY_DAY_HAS_OPEN_SETTLEMENTS':
            'لا يمكن إنهاء اليوم / Cannot close the day while unresolved cash settlements remain open.',
      },
      appendRequestId: true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    SessionInvalidationBus.instance.removeListener(
      _sessionInvalidationListener,
    );
    stopLiveOrders(force: true);
    super.dispose();
  }
}
