import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';

class _StaticJsonAdapter implements HttpClientAdapter {
  _StaticJsonAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _rideView() {
  return <String, dynamic>{
    'id': 41,
    'status': 'captain_assigned',
    'pickup': <String, dynamic>{
      'latitude': 33.31456,
      'longitude': 44.36611,
      'label': 'Bismayah Gate',
    },
    'dropoff': <String, dynamic>{
      'latitude': 33.32091,
      'longitude': 44.39118,
      'label': 'Central Mall',
    },
    'proposedFareIqd': 14500,
    'agreedFareIqd': 16000,
    'captain': <String, dynamic>{
      'fullName': 'Captain Noor',
      'phone': '07711111111',
      'carMake': 'Toyota',
      'carModel': 'Corolla',
      'carYear': 2022,
      'carColor': 'Silver',
      'vehicleType': 'sedan',
      'plateNumber': 'TX-001',
    },
  };
}

Map<String, dynamic> _assignmentEnvelope() {
  return <String, dynamic>{
    'ride': _rideView(),
    'assignment': <String, dynamic>{
      'rideId': 41,
      'status': 'captain_assigned',
      'customerFare': 14500,
      'finalFare': 16000,
      'currency': 'IQD',
      'pickupAddress': 'Bismayah Gate',
      'pickupLatitude': 33.31456,
      'pickupLongitude': 44.36611,
      'destinationAddress': 'Central Mall',
      'destinationLatitude': 33.32091,
      'destinationLongitude': 44.39118,
      'routeDistance': 1820,
      'routeDuration': 480,
      'estimatedArrivalMinutes': 6,
      'assignedAt': '2026-07-13T10:00:00.000Z',
      'captain': <String, dynamic>{
        'captainId': 77,
        'captainName': 'Captain Noor',
        'captainPhoto': 'https://cdn.example/captain.jpg',
        'captainRating': 4.9,
        'captainRatingCount': 128,
        'captainCompletedTrips': 128,
        'captainPhone': '07711111111',
        'captainLatitude': 33.315,
        'captainLongitude': 44.367,
        'captainHeading': 180,
        'captainDistanceMeters': 220,
        'captainEstimatedArrivalMinutes': 6,
      },
      'vehicle': <String, dynamic>{
        'vehicleId': 5,
        'vehicleMake': 'Toyota',
        'vehicleModel': 'Corolla',
        'vehicleYear': 2022,
        'vehicleColor': 'Silver',
        'vehicleType': 'sedan',
        'vehiclePlate': 'TX-001',
        'vehicleNumber': 'TX-001',
        'vehicleImage': 'https://cdn.example/car.jpg',
      },
    },
    'offers': <Map<String, dynamic>>[],
    'latestLocation': <String, dynamic>{
      'latitude': 33.315,
      'longitude': 44.367,
      'headingDeg': 180,
    },
  };
}

Map<String, dynamic> _wrappedEnvelope() {
  return <String, dynamic>{'ride': _assignmentEnvelope()};
}

Map<String, dynamic> _assignedRideEnvelopeWithOffers() {
  final ride = taxiRideViewFromEnvelope(_assignmentEnvelope());
  return <String, dynamic>{
    'ride': ride,
    'assignment': _assignmentEnvelope()['assignment'],
    'offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 12,
        'offerId': 12,
        'bidId': 12,
        'captainUserId': 77,
        'captainId': 77,
        'status': 'active',
        'offeredFareIqd': 16000,
        'etaMinutes': 6,
      },
    ],
    'bidQueue': <String, dynamic>{
      'currentBidId': 12,
      'currentOfferId': 12,
      'queueSize': 1,
      'queue': <Map<String, dynamic>>[
        <String, dynamic>{
          'bidId': 12,
          'offerId': 12,
          'captainUserId': 77,
          'status': 'active',
          'queuePosition': 1,
        },
      ],
    },
    'latestLocation': <String, dynamic>{
      'latitude': 33.315,
      'longitude': 44.367,
      'headingDeg': 180,
    },
  };
}

void main() {
  test('TaxiApi unwraps direct current ride envelopes', () async {
    final dio = Dio()..httpClientAdapter = _StaticJsonAdapter(_assignmentEnvelope());
    dio.options.baseUrl = 'http://127.0.0.1';
    final api = TaxiApi(dio);

    final payload = await api.getCurrentRideForCustomer();
    final ride = taxiRideViewFromEnvelope(payload);

    expect(payload, isNotNull);
    expect(payload!['assignment'], isA<Map>());
    expect(payload['ride'], isA<Map>());
    expect(ride, isNotNull);
    expect(ride!['id'], 41);
    expect(ride['status'], 'captain_assigned');
    expect(ride['assignment']['rideId'], 41);
    expect(ride['vehicle']['vehiclePlate'], 'TX-001');
  });

  test('TaxiApi unwraps nested current ride envelopes', () async {
    final dio = Dio()..httpClientAdapter = _StaticJsonAdapter(_wrappedEnvelope());
    dio.options.baseUrl = 'http://127.0.0.1';
    final api = TaxiApi(dio);

    final payload = await api.getCurrentRideForCaptain();
    final ride = taxiRideViewFromEnvelope(payload);

    expect(payload, isNotNull);
    expect(payload!['assignment'], isA<Map>());
    expect(payload['ride'], isA<Map>());
    expect(ride, isNotNull);
    expect(ride!['id'], 41);
    expect(ride['status'], 'captain_assigned');
    expect(ride['assignment']['rideId'], 41);
    expect(ride['captain']['captainName'], 'Captain Noor');
  });

  test('TaxiApi preserves offer collections when the ride view already carries assignment data', () async {
    final dio = Dio()
      ..httpClientAdapter = _StaticJsonAdapter(_assignedRideEnvelopeWithOffers());
    dio.options.baseUrl = 'http://127.0.0.1';
    final api = TaxiApi(dio);

    final payload = await api.getCurrentRideForCustomer();
    final ride = taxiRideViewFromEnvelope(payload);

    expect(payload, isNotNull);
    expect(payload!['offers'], isA<List>());
    expect(payload['bidQueue'], isA<Map>());
    expect(payload['assignment'], isA<Map>());
    expect(ride, isNotNull);
    expect(ride!['assignment'], isA<Map>());
    expect(ride['vehicle']['vehiclePlate'], 'TX-001');
  });
}
