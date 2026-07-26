import 'package:dio/dio.dart';

import '../../orders/models/order_revision_model.dart';

class DeliveryOrderActionReason {
  final String reasonCode;
  final String label;
  final bool allowsOtherText;

  const DeliveryOrderActionReason({
    required this.reasonCode,
    required this.label,
    required this.allowsOtherText,
  });

  factory DeliveryOrderActionReason.fromMap(Map<String, dynamic> map) {
    final labelAr = '${map['reasonLabelAr'] ?? ''}'.trim();
    final labelEn = '${map['reasonLabelEn'] ?? ''}'.trim();
    return DeliveryOrderActionReason(
      reasonCode: '${map['reasonCode'] ?? ''}'.trim(),
      label: labelAr.isNotEmpty ? labelAr : labelEn,
      allowsOtherText: map['allowsOtherText'] == true,
    );
  }
}

class DeliveryApi {
  final Dio dio;
  bool _courierModuleUnavailable = false;

  DeliveryApi(this.dio);

  Map<String, dynamic> _requestExtra({
    required bool skipTerminalSessionInvalidation,
  }) {
    if (!skipTerminalSessionInvalidation) return const <String, dynamic>{};
    return const <String, dynamic>{'skipTerminalSessionInvalidation': true};
  }

  Future<List<dynamic>> currentOrders({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final response = await dio.get(
      '/api/delivery/orders/current',
      options: Options(
        extra: _requestExtra(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ),
      ),
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> history({String? date}) async {
    final response = await dio.get(
      '/api/delivery/orders/history',
      queryParameters: date == null ? null : {'date': date},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<void> claimOrder(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/claim');
  }

  Future<void> startOrder(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/start');
  }

  Future<void> markArrived(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/arrived');
  }

  Future<void> markDelivered(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/delivered');
  }

  Future<Map<String, dynamic>> orderDetailV2(int orderId) async {
    final response = await dio.get('/api/delivery/orders/$orderId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<OrderRevisionModel>> listOrderRevisions(int orderId) async {
    final response = await dio.get('/api/delivery/orders/$orderId/revisions');
    final data = Map<String, dynamic>.from(response.data as Map? ?? const {});
    final items = List<dynamic>.from(data['items'] as List? ?? const []);
    return items
        .whereType<Map>()
        .map(
          (entry) =>
              OrderRevisionModel.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  /// Canonical courier earnings report: today/month totals, completed counts,
  /// delivery-fee sum, and per-order rows (computed server-side from this
  /// courier's delivered orders only).
  Future<Map<String, dynamic>> deliveryEarnings() async {
    final response = await dio.get('/api/delivery/earnings');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Courier ratings with their linked order ids (the rating lives on the order).
  Future<Map<String, dynamic>> deliveryRatings() async {
    final response = await dio.get('/api/delivery/ratings');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> upsertPresence({
    double? latitude,
    double? longitude,
    int? orderId,
    bool isOnline = true,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final payload = <String, dynamic>{'isOnline': isOnline};
    if (latitude != null) payload['latitude'] = latitude;
    if (longitude != null) payload['longitude'] = longitude;
    if (orderId != null) payload['orderId'] = orderId;
    if (headingDeg != null) payload['headingDeg'] = headingDeg;
    if (speedKmh != null) payload['speedKmh'] = speedKmh;
    if (accuracyM != null) payload['accuracyM'] = accuracyM;
    final response = await dio.post(
      '/api/courier/presence',
      data: payload,
      options: Options(
        extra: _requestExtra(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endDay({String? date}) async {
    final response = await dio.post(
      '/api/delivery/end-day',
      data: {'date': date},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endDayReadiness({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final response = await dio.get(
      '/api/delivery/end-day/readiness',
      options: Options(
        extra: _requestExtra(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analytics({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final response = await dio.get(
      '/api/delivery/analytics',
      options: Options(
        extra: _requestExtra(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptOrderV2(
    int orderId, {
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/accept',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectOrderV2(
    int orderId, {
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/reject',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> pickedUpV2(int orderId, {String? note}) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/picked-up',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> arrivedV2(int orderId, {String? note}) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/arrived',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deliveredV2(int orderId, {String? note}) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/delivered',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestCancelV2(
    int orderId, {
    required String reasonCode,
    String? reasonText,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/courier/request-cancel',
      data: {
        'reasonCode': reasonCode,
        if (reasonText != null && reasonText.trim().isNotEmpty)
          'reasonText': reasonText.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<DeliveryOrderActionReason>> listOrderActionReasons({
    required String actorScope,
    required String actionKind,
  }) async {
    final response = await dio.get(
      '/api/orders/action-reasons',
      queryParameters: {'actorScope': actorScope, 'actionKind': actionKind},
    );
    final map = Map<String, dynamic>.from(response.data as Map? ?? const {});
    final items = List<dynamic>.from(map['items'] as List? ?? const []);
    return items
        .map(
          (entry) => DeliveryOrderActionReason.fromMap(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .where((entry) => entry.reasonCode.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> orderChatMessagesV2(
    int orderId, {
    int limit = 120,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (beforeId != null) query['beforeId'] = beforeId;
    final response = await dio.get(
      '/api/orders/$orderId/chat/messages',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendOrderChatMessageV2(
    int orderId, {
    required String message,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/chat/messages',
      data: {'message': message},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final data = await _getCourierMapWithFallback(
      courierPath: '/api/courier/dashboard',
      legacyPath: '/api/delivery/analytics',
      queryParameters: query,
      skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
    );
    if (data.containsKey('day') || data.containsKey('month')) {
      return {'kpis': data};
    }
    return data;
  }

  Future<List<dynamic>> requestsV2({
    int limit = 40,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) return const <dynamic>[];
    try {
      final response = await dio.get(
        '/api/courier/requests',
        queryParameters: {'limit': limit, 'offset': offset},
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      final rows = map['requests'] ?? map['items'] ?? const <dynamic>[];
      return List<dynamic>.from(rows as List);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        return const <dynamic>[];
      }
      rethrow;
    }
  }

  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) {
      final legacyCurrent = await currentOrders(
        skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
      ).catchError((_) => <dynamic>[]);
      return legacyCurrent;
    }
    try {
      final query = <String, dynamic>{'limit': limit, 'offset': offset};
      if (status != null) query['status'] = status;
      if (merchantId != null) query['merchantId'] = merchantId;
      final response = await dio.get(
        '/api/courier/orders',
        queryParameters: query,
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      return List<dynamic>.from(map['orders'] as List? ?? const []);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        final legacyCurrent = await currentOrders(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ).catchError((_) => <dynamic>[]);
        return legacyCurrent;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final data = await _getCourierMapWithFallback(
      courierPath: '/api/courier/reports',
      legacyPath: '/api/delivery/analytics',
      queryParameters: query,
      skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
    );
    if (data.containsKey('day') || data.containsKey('month')) {
      return {'summary': data};
    }
    return data;
  }

  Future<Map<String, dynamic>> competitionsV2({
    String scope = 'active',
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) {
      return const {'competitions': <dynamic>[]};
    }
    try {
      final response = await dio.get(
        '/api/courier/competitions',
        queryParameters: {'scope': scope},
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        return const {'competitions': <dynamic>[]};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> competitionDetailsV2(int competitionId) async {
    final response = await dio.get('/api/courier/competitions/$competitionId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> competitionAchievementsSummaryV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) {
      return const {'summary': <String, dynamic>{}};
    }
    try {
      final response = await dio.get(
        '/api/courier/competitions/achievements/summary',
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        return const {'summary': <String, dynamic>{}};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> competitionProgressV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) {
      return const {'items': <dynamic>[]};
    }
    try {
      final response = await dio.get(
        '/api/courier/competition-progress',
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      final raw = Map<String, dynamic>.from(response.data as Map);
      final dynamic rawItems =
          raw['items'] ?? raw['progress'] ?? const <dynamic>[];
      final items = rawItems is List
          ? List<dynamic>.from(rawItems)
          : const <dynamic>[];
      return {...raw, 'items': items, 'progress': items};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        return const {'items': <dynamic>[]};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> earningsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final response = await dio.get(
      '/api/courier/earnings',
      queryParameters: {
        'period': period,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> ordersGroupedByMerchantV2({
    String? status,
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/courier/orders/grouped-by-merchant',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ---- Grouped multi-store delivery jobs (delivery closure §3) ----
  // Backend routes are mounted under /api/delivery (deliveryRouter).

  Future<Map<String, dynamic>?> currentGroupedJob({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    final response = await dio.get(
      '/api/delivery/delivery-jobs/current',
      options: Options(
        extra: _requestExtra(
          skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
        ),
      ),
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final job = map['job'];
    return job == null ? null : Map<String, dynamic>.from(job as Map);
  }

  Future<List<dynamic>> listGroupedJobs() async {
    final response = await dio.get('/api/delivery/delivery-jobs');
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['jobs'] as List? ?? const []);
  }

  Future<List<dynamic>> groupedJobHistory({int limit = 50}) async {
    final response = await dio.get(
      '/api/delivery/delivery-jobs/history',
      queryParameters: {'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['jobs'] as List? ?? const []);
  }

  Future<Map<String, dynamic>> groupedJobDetails(int deliveryJobId) async {
    final response = await dio.get(
      '/api/delivery/delivery-jobs/$deliveryJobId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> _jobAction(
    int deliveryJobId,
    String action, {
    int? expectedVersion,
    Map<String, dynamic>? extraBody,
  }) async {
    final response = await dio.post(
      '/api/delivery/delivery-jobs/$deliveryJobId/$action',
      data: {
        ...?(expectedVersion == null
            ? null
            : <String, dynamic>{'expectedVersion': expectedVersion}),
        ...?extraBody,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acknowledgeJob(int id, {int? expectedVersion}) =>
      _jobAction(id, 'acknowledge', expectedVersion: expectedVersion);

  Future<Map<String, dynamic>> headingToPickups(
    int id, {
    int? expectedVersion,
  }) => _jobAction(id, 'heading-to-pickups', expectedVersion: expectedVersion);

  Future<Map<String, dynamic>> stopArrived(
    int id,
    int stopId, {
    int? expectedVersion,
  }) =>
      _jobAction(id, 'stops/$stopId/arrived', expectedVersion: expectedVersion);

  Future<Map<String, dynamic>> stopCollected(
    int id,
    int stopId, {
    int? expectedVersion,
  }) => _jobAction(
    id,
    'stops/$stopId/collected',
    expectedVersion: expectedVersion,
  );

  Future<Map<String, dynamic>> headingToCustomer(
    int id, {
    int? expectedVersion,
  }) => _jobAction(id, 'heading-to-customer', expectedVersion: expectedVersion);

  Future<Map<String, dynamic>> markGroupedDelivered(
    int id, {
    int? expectedVersion,
  }) => _jobAction(id, 'delivered', expectedVersion: expectedVersion);

  Future<Map<String, dynamic>> _getCourierMapWithFallback({
    required String courierPath,
    required String legacyPath,
    Map<String, dynamic>? queryParameters,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (_courierModuleUnavailable) {
      final legacy = await dio.get(
        legacyPath,
        queryParameters: queryParameters,
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      return Map<String, dynamic>.from(legacy.data as Map);
    }
    try {
      final response = await dio.get(
        courierPath,
        queryParameters: queryParameters,
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      _courierModuleUnavailable = true;
      final legacy = await dio.get(
        legacyPath,
        queryParameters: queryParameters,
        options: Options(
          extra: _requestExtra(
            skipTerminalSessionInvalidation: skipTerminalSessionInvalidation,
          ),
        ),
      );
      return Map<String, dynamic>.from(legacy.data as Map);
    }
  }
}
