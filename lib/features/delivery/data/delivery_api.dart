import 'package:dio/dio.dart';

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

  Future<List<dynamic>> currentOrders() async {
    final response = await dio.get('/api/delivery/orders/current');
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
    required double latitude,
    required double longitude,
    int? orderId,
    bool isOnline = true,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
  }) async {
    final payload = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'isOnline': isOnline,
    };
    if (orderId != null) payload['orderId'] = orderId;
    if (headingDeg != null) payload['headingDeg'] = headingDeg;
    if (speedKmh != null) payload['speedKmh'] = speedKmh;
    if (accuracyM != null) payload['accuracyM'] = accuracyM;
    final response = await dio.post('/api/courier/presence', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endDay({String? date}) async {
    final response = await dio.post(
      '/api/delivery/end-day',
      data: {'date': date},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endDayReadiness() async {
    final response = await dio.get('/api/delivery/end-day/readiness');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analytics() async {
    final response = await dio.get('/api/delivery/analytics');
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
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final data = await _getCourierMapWithFallback(
      courierPath: '/api/courier/dashboard',
      legacyPath: '/api/delivery/analytics',
      queryParameters: query,
    );
    if (data.containsKey('day') || data.containsKey('month')) {
      return {'kpis': data};
    }
    return data;
  }

  Future<List<dynamic>> requestsV2({int limit = 40, int offset = 0}) async {
    if (_courierModuleUnavailable) return const <dynamic>[];
    try {
      final response = await dio.get(
        '/api/courier/requests',
        queryParameters: {'limit': limit, 'offset': offset},
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
  }) async {
    if (_courierModuleUnavailable) {
      final legacyCurrent = await currentOrders().catchError(
        (_) => <dynamic>[],
      );
      return legacyCurrent;
    }
    try {
      final query = <String, dynamic>{'limit': limit, 'offset': offset};
      if (status != null) query['status'] = status;
      if (merchantId != null) query['merchantId'] = merchantId;
      final response = await dio.get(
        '/api/courier/orders',
        queryParameters: query,
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      return List<dynamic>.from(map['orders'] as List? ?? const []);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _courierModuleUnavailable = true;
        final legacyCurrent = await currentOrders().catchError(
          (_) => <dynamic>[],
        );
        return legacyCurrent;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final data = await _getCourierMapWithFallback(
      courierPath: '/api/courier/reports',
      legacyPath: '/api/delivery/analytics',
      queryParameters: query,
    );
    if (data.containsKey('day') || data.containsKey('month')) {
      return {'summary': data};
    }
    return data;
  }

  Future<Map<String, dynamic>> competitionsV2({String scope = 'active'}) async {
    if (_courierModuleUnavailable) {
      return const {'competitions': <dynamic>[]};
    }
    try {
      final response = await dio.get(
        '/api/courier/competitions',
        queryParameters: {'scope': scope},
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

  Future<Map<String, dynamic>> competitionAchievementsSummaryV2() async {
    if (_courierModuleUnavailable) {
      return const {'summary': <String, dynamic>{}};
    }
    try {
      final response = await dio.get(
        '/api/courier/competitions/achievements/summary',
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

  Future<Map<String, dynamic>> competitionProgressV2() async {
    if (_courierModuleUnavailable) {
      return const {'items': <dynamic>[]};
    }
    try {
      final response = await dio.get('/api/courier/competition-progress');
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

  Future<Map<String, dynamic>> _getCourierMapWithFallback({
    required String courierPath,
    required String legacyPath,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (_courierModuleUnavailable) {
      final legacy = await dio.get(
        legacyPath,
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(legacy.data as Map);
    }
    try {
      final response = await dio.get(
        courierPath,
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      _courierModuleUnavailable = true;
      final legacy = await dio.get(
        legacyPath,
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(legacy.data as Map);
    }
  }
}
