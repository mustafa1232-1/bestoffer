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
