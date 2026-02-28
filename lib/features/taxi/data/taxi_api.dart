import 'dart:convert';

import 'package:dio/dio.dart';

class TaxiLiveEvent {
  final String event;
  final Map<String, dynamic> data;

  const TaxiLiveEvent({required this.event, required this.data});
}

class TaxiApi {
  final Dio dio;

  TaxiApi(this.dio);

  Future<Map<String, dynamic>?> getCurrentRideForCustomer() async {
    final response = await dio.get('/api/taxi/rides/current');
    final map = Map<String, dynamic>.from(response.data as Map);
    final ride = map['ride'];
    if (ride is Map) {
      return Map<String, dynamic>.from(ride);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getCurrentRideForCaptain() async {
    final response = await dio.get('/api/taxi/captain/current-ride');
    final map = Map<String, dynamic>.from(response.data as Map);
    final ride = map['ride'];
    if (ride is Map) {
      return Map<String, dynamic>.from(ride);
    }
    return null;
  }

  Future<Map<String, dynamic>> getCaptainDashboard({
    String period = 'month',
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/taxi/captain/dashboard',
      queryParameters: {'period': period, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainProfile() async {
    final response = await dio.get('/api/taxi/captain/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainSubscription() async {
    final response = await dio.get('/api/taxi/captain/subscription');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestCaptainCashPayment() async {
    final response = await dio.post(
      '/api/taxi/captain/subscription/request-cash-payment',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestCaptainProfileEdit({
    required Map<String, dynamic> requestedChanges,
    String? captainNote,
  }) async {
    final response = await dio.post(
      '/api/taxi/captain/profile-edit-requests',
      data: {'requestedChanges': requestedChanges, 'captainNote': captainNote},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createRide({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String pickupLabel,
    required String dropoffLabel,
    required int proposedFareIqd,
    int searchRadiusM = 2000,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides',
      data: {
        'pickupLatitude': pickupLatitude,
        'pickupLongitude': pickupLongitude,
        'dropoffLatitude': dropoffLatitude,
        'dropoffLongitude': dropoffLongitude,
        'pickupLabel': pickupLabel,
        'dropoffLabel': dropoffLabel,
        'proposedFareIqd': proposedFareIqd,
        'searchRadiusM': searchRadiusM,
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> upsertCaptainPresence({
    required bool isOnline,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
    int radiusM = 4000,
  }) async {
    final response = await dio.post(
      '/api/taxi/captain/presence',
      data: {
        'isOnline': isOnline,
        'latitude': latitude,
        'longitude': longitude,
        'headingDeg': headingDeg,
        'speedKmh': speedKmh,
        'accuracyM': accuracyM,
        'radiusM': radiusM,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listNearbyRequests({
    int radiusM = 4000,
    int limit = 30,
  }) async {
    final response = await dio.get(
      '/api/taxi/captain/nearby-requests',
      queryParameters: {'radiusM': radiusM, 'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getCaptainHistory({
    String period = 'month',
    int limit = 30,
  }) async {
    final response = await dio.get(
      '/api/taxi/captain/history',
      queryParameters: {'period': period, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createBid({
    required int rideId,
    required int offeredFareIqd,
    int? etaMinutes,
    String? note,
  }) async {
    final body = <String, dynamic>{'offeredFareIqd': offeredFareIqd};
    if (etaMinutes != null) {
      body['etaMinutes'] = etaMinutes;
    }
    if (note?.trim().isNotEmpty ?? false) {
      body['note'] = note!.trim();
    }

    final response = await dio.post('/api/taxi/rides/$rideId/bids', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> markArrived(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/arrive');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startRide(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/start');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> completeRide(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/complete');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateRideLocation({
    required int rideId,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/location',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        'headingDeg': headingDeg,
        'speedKmh': speedKmh,
        'accuracyM': accuracyM,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getRideDetails(int rideId) async {
    final response = await dio.get('/api/taxi/rides/$rideId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelRide(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/cancel');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createShareToken(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/share-token');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptBid({
    required int rideId,
    required int bidId,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/bids/$bidId/accept',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectCurrentBid({required int rideId}) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/bids/current/reject',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> counterOfferCurrentBid({
    required int rideId,
    required int offeredFareIqd,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/bids/current/counter',
      data: {
        'offeredFareIqd': offeredFareIqd,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRideChat({
    required int rideId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/taxi/rides/$rideId/chat',
      queryParameters: {'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['messages'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> sendRideChatMessage({
    required int rideId,
    required String messageText,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/chat',
      data: {'messageText': messageText.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getRideCallState({
    required int rideId,
    int signalLimit = 160,
  }) async {
    final response = await dio.get(
      '/api/taxi/rides/$rideId/call',
      queryParameters: {'signalLimit': signalLimit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startRideCall({required int rideId}) async {
    final response = await dio.post('/api/taxi/rides/$rideId/call/start');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendRideCallSignal({
    required int rideId,
    int? sessionId,
    required String signalType,
    Map<String, dynamic>? signalPayload,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/call/signal',
      data: {
        if (sessionId != null) 'sessionId': sessionId,
        'signalType': signalType,
        if (signalPayload != null) 'signalPayload': signalPayload,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endRideCall({
    required int rideId,
    String status = 'ended',
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/call/end',
      data: {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Stream<TaxiLiveEvent> streamEvents() async* {
    final response = await dio.get<ResponseBody>(
      '/api/taxi/stream',
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
        headers: const {'Accept': 'text/event-stream'},
      ),
    );

    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var eventName = 'message';
    var dataBuffer = '';

    await for (final line in lines) {
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }

      if (line.startsWith('data:')) {
        final chunk = line.substring(5).trimLeft();
        dataBuffer = dataBuffer.isEmpty ? chunk : '$dataBuffer\n$chunk';
        continue;
      }

      if (line.isNotEmpty) continue;
      if (dataBuffer.isEmpty) {
        eventName = 'message';
        continue;
      }

      final payload = _parseSsePayload(dataBuffer);
      yield TaxiLiveEvent(event: eventName, data: payload);

      eventName = 'message';
      dataBuffer = '';
    }
  }

  Map<String, dynamic> _parseSsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'value': decoded};
    } catch (_) {
      return {'raw': raw};
    }
  }
}
