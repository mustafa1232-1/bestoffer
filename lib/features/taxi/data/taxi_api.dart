import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../auth/state/auth_controller.dart';

final taxiApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio, realtime: ref.read(maslakiRealtimeServiceProvider));
});

/// نموذج event حي قادم من SSE أو قناة التاكسي الحية.
class TaxiLiveEvent {
  final String event;
  final Map<String, dynamic> data;
  final int? eventId;

  const TaxiLiveEvent({required this.event, required this.data, this.eventId});
}

/// عميل API الخاص بالتكسي في الواجهة.
///
/// Critical notes:
/// - هذا الملف مسؤول فقط عن ترجمة Dart payloads إلى REST calls.
/// - منطق الانتقالات والتحقق من الصلاحيات يبقى في backend وفي controllers.
class TaxiApi {
  final Dio dio;
  final MaslakiRealtimeClient? realtime;

  TaxiApi(this.dio, {this.realtime});

  /// يجلب الرحلة الحالية للعميل إن وجدت.
  Future<Map<String, dynamic>?> getCurrentRideForCustomer() async {
    final response = await dio.get('/api/taxi/rides/current');
    return _unwrapCurrentRideEnvelope(response.data);
  }

  /// يجلب الرحلة الحالية للكابتن.
  Future<Map<String, dynamic>?> getCurrentRideForCaptain() async {
    final response = await dio.get('/api/taxi/captain/current-ride');
    return _unwrapCurrentRideEnvelope(response.data);
  }

  /// The taxi backend has historically emitted both wrapped and direct current
  /// ride bodies while the UI evolved. Preserve the outer envelope whenever it
  /// already carries offer/queue collections so the customer screen keeps the
  /// authoritative negotiation state instead of dropping it with the nested
  /// `ride` view.
  Map<String, dynamic>? _unwrapCurrentRideEnvelope(dynamic data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    final inner = map['ride'];
    if (inner is! Map) return null; // no active ride
    final innerMap = Map<String, dynamic>.from(inner);
    final topLevelTaxiCollections = map.containsKey('offers') ||
        map.containsKey('offerQueue') ||
        map.containsKey('bidQueue') ||
        map.containsKey('bids') ||
        map.containsKey('currentOffer') ||
        map.containsKey('currentBid') ||
        map.containsKey('events') ||
        map.containsKey('chatMessages') ||
        map.containsKey('latestLocation') ||
        map.containsKey('assignment');
    if (topLevelTaxiCollections) {
      return map;
    }
    final looksLikeEnvelope = innerMap['ride'] is Map ||
        innerMap['assignment'] is Map ||
        innerMap.containsKey('offers') ||
        innerMap.containsKey('bids') ||
        innerMap.containsKey('latestLocation');
    return looksLikeEnvelope ? innerMap : map;
  }

  Future<List<Map<String, dynamic>>> listMyRideHistory({
    String period = 'month',
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/taxi/rides/history/me',
      queryParameters: {'period': period, 'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listNearbyCaptains({
    required double latitude,
    required double longitude,
    int radiusM = 15000,
    int limit = 60,
  }) async {
    final response = await dio.get(
      '/api/taxi/captains/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radiusM': radiusM,
        'limit': limit,
      },
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
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

  /// ينشئ طلب رحلة جديداً من جهة العميل.
  Future<Map<String, dynamic>> createRide({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String pickupLabel,
    required String dropoffLabel,
    required int proposedFareIqd,
    int searchRadiusM = 15000,
    String? couponCode,
    String scheduleMode = 'now',
    int? scheduledRideId,
    DateTime? scheduledFor,
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
        if (couponCode != null && couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim().toUpperCase(),
        if (scheduleMode.trim().toLowerCase() == 'scheduled')
          'scheduleMode': 'scheduled'
        else
          'scheduleMode': 'now',
        if (scheduledRideId != null && scheduledRideId > 0)
          'scheduledRideId': scheduledRideId,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toIso8601String(),
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// يحدث presence وموقع الكابتن الحالي.
  Future<Map<String, dynamic>> upsertCaptainPresence({
    required bool isOnline,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
    int radiusM = 15000,
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
    int radiusM = 15000,
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

  /// يرسل bid من الكابتن على رحلة محددة.
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

  Future<Map<String, dynamic>> acceptCustomerFare({required int rideId}) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/captain/accept-customer-fare',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> declineRideRequest({required int rideId}) async {
    final response = await dio.post('/api/taxi/rides/$rideId/decline');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> raiseRideFare({
    required int rideId,
    required int proposedFareIqd,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/raise-fare',
      data: {'proposedFareIqd': proposedFareIqd},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// ينفذ انتقال الوصول إلى موقع الالتقاط.
  Future<Map<String, dynamic>> markArrived(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/arrive');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// يبدأ الرحلة فعلياً.
  Future<Map<String, dynamic>> startRide(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/start');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// ينهي الرحلة من جهة الكابتن.
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

  /// إلغاء الرحلة من جهة الزبون. سبب الإلغاء إلزامي في الخادم.
  Future<Map<String, dynamic>> cancelRide(
    int rideId, {
    required String reasonCode,
    String? reasonText,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/cancel',
      data: {
        'reasonCode': reasonCode,
        if (reasonText != null && reasonText.trim().isNotEmpty)
          'reasonText': reasonText.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// إلغاء الرحلة من جهة الكابتن (مسموح فقط قبل التوجه إلى الزبون).
  Future<Map<String, dynamic>> cancelRideByCaptain(
    int rideId, {
    required String reasonCode,
    String? reasonText,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/captain/cancel',
      data: {
        'reasonCode': reasonCode,
        if (reasonText != null && reasonText.trim().isNotEmpty)
          'reasonText': reasonText.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// يفتح حالة طارئة/طلب مساعدة على الرحلة (لا يلغيها؛ ينشئ تذكرة عاجلة).
  Future<Map<String, dynamic>> raiseRideEmergency(
    int rideId, {
    String category = 'safety',
    String? message,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/emergency',
      data: {
        'category': category,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rateRide({
    required int rideId,
    required int rating,
    String? review,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/rate',
      data: {
        'rating': rating,
        if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
      },
    );
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

  Future<Map<String, dynamic>> rejectBid({
    required int rideId,
    required int bidId,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/bids/$bidId/reject',
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

  Future<Map<String, dynamic>> counterOfferBid({
    required int rideId,
    required int bidId,
    required int offeredFareIqd,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/bids/$bidId/counter',
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

  Future<List<int>> listRideSharedFriendIds({required int rideId}) async {
    final response = await dio.get('/api/taxi/rides/$rideId/share/friends');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item['friendUserId'] ?? item['friend_user_id'])
        .map((value) => int.tryParse('$value'))
        .whereType<int>()
        .toList();
  }

  Future<Map<String, dynamic>> shareRideWithFriends({
    required int rideId,
    required List<int> friendUserIds,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/share/friends',
      data: {'friendUserIds': friendUserIds},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getSharedRideTrack({required int rideId}) async {
    final response = await dio.get('/api/taxi/rides/$rideId/shared-track');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> publicTrackByToken(String token) async {
    final response = await dio.get('/api/taxi/public/track/$token');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPublicShareToken(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/share-token');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Stream<TaxiLiveEvent> streamPublicTrackByToken(String token) async* {
    final response = await dio.get<ResponseBody>(
      '/api/taxi/public/track/$token/stream',
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
    int? parsedEventId;

    await for (final line in lines) {
      if (line.startsWith('retry:')) {
        continue;
      }

      if (line.startsWith('id:')) {
        parsedEventId = int.tryParse(line.substring(3).trim());
        continue;
      }

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
      yield TaxiLiveEvent(
        event: eventName,
        data: payload,
        eventId: parsedEventId,
      );

      eventName = 'message';
      dataBuffer = '';
      parsedEventId = null;
    }
  }

  Future<Map<String, dynamic>> getRideCallState(int rideId) async {
    final response = await dio.get('/api/taxi/rides/$rideId/call');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startRideCall(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/call/start');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendRideCallSignal({
    required int rideId,
    required String signalType,
    Map<String, dynamic>? payload,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/call/signal',
      data: {
        'signalType': signalType,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rebookRide(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/rebook');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endRideCall(int rideId) async {
    final response = await dio.post('/api/taxi/rides/$rideId/call/end');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listSavedPlaces() async {
    final response = await dio.get('/api/taxi/saved-places');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createSavedPlace(
    Map<String, dynamic> payload,
  ) async {
    final response = await dio.post('/api/taxi/saved-places', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateSavedPlace({
    required int id,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.patch(
      '/api/taxi/saved-places/$id',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteSavedPlace(int id) async {
    await dio.delete('/api/taxi/saved-places/$id');
  }

  Future<Map<String, dynamic>> importSavedPlacesFromDeliveryAddresses() async {
    final response = await dio.post(
      '/api/taxi/saved-places/import-default-addresses',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listFavoriteTrips() async {
    final response = await dio.get('/api/taxi/favorite-trips');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createFavoriteTrip(
    Map<String, dynamic> payload,
  ) async {
    final response = await dio.post('/api/taxi/favorite-trips', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateFavoriteTrip({
    required int id,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.patch(
      '/api/taxi/favorite-trips/$id',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteFavoriteTrip(int id) async {
    await dio.delete('/api/taxi/favorite-trips/$id');
  }

  Future<List<Map<String, dynamic>>> listScheduledRides({
    String status = 'scheduled',
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/taxi/scheduled-rides',
      queryParameters: {'status': status, 'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createScheduledRide({
    required Map<String, dynamic> pickupSnapshot,
    required Map<String, dynamic> dropoffSnapshot,
    required int proposedFareIqd,
    required DateTime scheduleFor,
    String? note,
    String? couponCode,
  }) async {
    final response = await dio.post(
      '/api/taxi/scheduled-rides',
      data: {
        'pickupSnapshot': pickupSnapshot,
        'dropoffSnapshot': dropoffSnapshot,
        'proposedFareIqd': proposedFareIqd,
        'scheduleFor': scheduleFor.toIso8601String(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (couponCode != null && couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim().toUpperCase(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelScheduledRide(int id) async {
    final response = await dio.post('/api/taxi/scheduled-rides/$id/cancel');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listMyCoupons() async {
    final response = await dio.get('/api/taxi/coupons/mine');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> previewCoupon({
    required String couponCode,
    required int proposedFareIqd,
  }) async {
    final response = await dio.post(
      '/api/taxi/coupons/preview',
      data: {
        'couponCode': couponCode.trim().toUpperCase(),
        'proposedFareIqd': proposedFareIqd,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> complaintEligibility(int rideId) async {
    final response = await dio.get(
      '/api/taxi/rides/$rideId/complaint-eligibility',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listMyComplaints({int limit = 80}) async {
    final response = await dio.get(
      '/api/taxi/complaints',
      queryParameters: {'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createComplaint({
    required int tripId,
    required String category,
    required String reason,
    String? details,
    String? attachmentUrl,
  }) async {
    final response = await dio.post(
      '/api/taxi/complaints',
      data: {
        'tripId': tripId,
        'category': category,
        'reason': reason,
        if (details != null && details.trim().isNotEmpty)
          'details': details.trim(),
        if (attachmentUrl != null && attachmentUrl.trim().isNotEmpty)
          'attachmentUrl': attachmentUrl.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rateRiderByCaptain({
    required int rideId,
    required int rating,
    String? category,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/taxi/rides/$rideId/rider-rating',
      data: {
        'rating': rating,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainSubscriptionLedger({
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/taxi/captain/subscription/ledger',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainContests({
    bool refresh = false,
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/taxi/captain/contests',
      queryParameters: {'refresh': refresh, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainRewards({int limit = 80}) async {
    final response = await dio.get(
      '/api/taxi/captain/rewards',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCaptainGovernanceStatus() async {
    final response = await dio.get('/api/taxi/captain/status');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listAdminTaxiCoupons({
    bool includeInactive = true,
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/coupons',
      queryParameters: {'includeInactive': includeInactive},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> upsertAdminTaxiCoupon({
    int? couponId,
    required Map<String, dynamic> payload,
  }) async {
    final response = couponId == null
        ? await dio.post('/api/admin/taxi/coupons', data: payload)
        : await dio.patch('/api/admin/taxi/coupons/$couponId', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteAdminTaxiCoupon(int couponId) async {
    await dio.delete('/api/admin/taxi/coupons/$couponId');
  }

  Future<Map<String, dynamic>> adminTaxiCouponTargetLookup({
    String query = '',
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/coupons/targets/lookups',
      queryParameters: {'query': query, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminTaxiCaptainDetails(
    int captainUserId,
  ) async {
    final response = await dio.get(
      '/api/admin/taxi/captains/$captainUserId/details',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminIssueCaptainGift({
    required int captainUserId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.post(
      '/api/admin/taxi/captains/$captainUserId/gifts',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminIssueCaptainWarning({
    required int captainUserId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.post(
      '/api/admin/taxi/captains/$captainUserId/warnings',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminSetCaptainStatus({
    required int captainUserId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.patch(
      '/api/admin/taxi/captains/$captainUserId/status',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listAdminTaxiContests({
    bool includeInactive = true,
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/contests',
      queryParameters: {'includeInactive': includeInactive},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> upsertAdminTaxiContest({
    int? contestId,
    required Map<String, dynamic> payload,
  }) async {
    final response = contestId == null
        ? await dio.post('/api/admin/taxi/contests', data: payload)
        : await dio.patch('/api/admin/taxi/contests/$contestId', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> finalizeAdminTaxiContest(int contestId) async {
    final response = await dio.post(
      '/api/admin/taxi/contests/$contestId/finalize',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteAdminTaxiContest(int contestId) async {
    await dio.delete('/api/admin/taxi/contests/$contestId');
  }

  Future<List<Map<String, dynamic>>> listAdminTaxiComplaints({
    String status = 'new',
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/complaints',
      queryParameters: {'status': status, 'limit': limit},
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> reviewAdminTaxiComplaint({
    required int complaintId,
    required String status,
    String? adminNote,
  }) async {
    final response = await dio.patch(
      '/api/admin/taxi/complaints/$complaintId/review',
      data: {
        'status': status,
        if (adminNote != null && adminNote.trim().isNotEmpty)
          'adminNote': adminNote.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminTaxiKpiOverview({
    String period = 'month',
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/kpi/overview',
      queryParameters: {'period': period},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminTaxiReports({
    required String type,
    int limit = 200,
  }) async {
    final response = await dio.get(
      '/api/admin/taxi/reports',
      queryParameters: {'type': type, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Stream<TaxiLiveEvent> streamEvents({int? lastEventId}) {
    return _streamSupabaseFirst(
      openRealtime: () async => await realtime?.subscribeUserChannel('taxi'),
      fallback: () => _streamEventsViaSse(lastEventId: lastEventId),
    );
  }

  Stream<TaxiLiveEvent> streamRideEvents({
    required int rideId,
    int? lastEventId,
  }) {
    return _streamSupabaseFirst(
      openRealtime: () async => await realtime?.subscribeUserChannel('taxi'),
      fallback: () => _streamEventsViaSse(lastEventId: lastEventId).where(
        (event) =>
            event.event == 'resync_required' ||
            _matchesRideEvent(event.data, rideId),
      ),
    ).where(
      (event) =>
          event.event == 'connected' ||
          event.event == 'resync_required' ||
          _matchesRideEvent(event.data, rideId),
    );
  }

  Stream<TaxiLiveEvent> _streamSupabaseFirst({
    required Future<Stream<MaslakiRealtimeEvent>?> Function() openRealtime,
    required Stream<TaxiLiveEvent> Function() fallback,
  }) {
    late final StreamController<TaxiLiveEvent> controller;
    StreamSubscription<dynamic>? activeSubscription;
    var usingFallback = false;

    Future<void> attachFallback() async {
      if (usingFallback || controller.isClosed) return;
      usingFallback = true;
      await activeSubscription?.cancel();
      activeSubscription = fallback().listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    }

    Future<void> bootstrap() async {
      try {
        final realtimeStream = await openRealtime();
        if (realtimeStream == null) {
          await attachFallback();
          return;
        }
        controller.add(
          const TaxiLiveEvent(event: 'connected', data: <String, dynamic>{}),
        );
        activeSubscription = realtimeStream.listen(
          (event) {
            controller.add(
              TaxiLiveEvent(
                event: event.event,
                data: event.data,
                eventId: event.eventId,
              ),
            );
          },
          onError: (_) => unawaited(attachFallback()),
          onDone: () => unawaited(attachFallback()),
          cancelOnError: false,
        );
      } catch (_) {
        await attachFallback();
      }
    }

    controller = StreamController<TaxiLiveEvent>(
      onListen: () {
        unawaited(bootstrap());
      },
      onCancel: () async {
        await activeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<TaxiLiveEvent> _streamEventsViaSse({int? lastEventId}) async* {
    final response = await dio.get<ResponseBody>(
      '/api/taxi/stream',
      queryParameters: {
        if (lastEventId != null && lastEventId > 0) 'lastEventId': lastEventId,
      },
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
        headers: {
          'Accept': 'text/event-stream',
          if (lastEventId != null && lastEventId > 0)
            'Last-Event-ID': '$lastEventId',
        },
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
    int? parsedEventId;

    await for (final line in lines) {
      if (line.startsWith('retry:')) {
        continue;
      }

      if (line.startsWith('id:')) {
        parsedEventId = int.tryParse(line.substring(3).trim());
        continue;
      }

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
      yield TaxiLiveEvent(
        event: eventName,
        data: payload,
        eventId: parsedEventId,
      );

      eventName = 'message';
      dataBuffer = '';
      parsedEventId = null;
    }
  }

  bool _matchesRideEvent(Map<String, dynamic> data, int rideId) {
    final rawRideId =
        data['rideId'] ??
        data['ride_id'] ??
        (data['ride'] is Map ? (data['ride'] as Map)['id'] : null);
    return int.tryParse('$rawRideId') == rideId;
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
