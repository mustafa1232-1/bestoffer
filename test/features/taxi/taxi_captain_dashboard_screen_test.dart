import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';
import 'package:maslaki/features/taxi/ui/taxi_captain_dashboard_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:core_maps/core_maps.dart';
import 'package:latlong2/latlong.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform(this.position);

  final Position position;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => position;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return position;
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() async* {}

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) async* {}

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeLocationPermissionService extends LocationPermissionService {
  const _FakeLocationPermissionService();

  @override
  Future<LocationPermissionStatus> getStatus() async {
    return const LocationPermissionStatus(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      accuracyStatus: LocationAccuracyStatus.precise,
    );
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async => getStatus();
}

class _FakeTaxiApi extends TaxiApi {
  _FakeTaxiApi({
    required this.nearbyRequests,
    required this.dashboard,
    required this.profile,
    required this.subscription,
    StreamController<TaxiLiveEvent>? streamController,
  }) : streamController =
           streamController ?? StreamController<TaxiLiveEvent>.broadcast(),
       super(Dio());

  final List<Map<String, dynamic>> nearbyRequests;
  final Map<String, dynamic> dashboard;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> subscription;
  final StreamController<TaxiLiveEvent> streamController;

  Map<String, dynamic>? currentRideEnvelope;
  final List<int> acceptedCustomerFareRideIds = [];
  int currentRideCalls = 0;

  @override
  Future<Map<String, dynamic>?> getCurrentRideForCaptain() async {
    currentRideCalls += 1;
    return currentRideEnvelope;
  }

  @override
  Future<Map<String, dynamic>> getCaptainDashboard({
    String period = 'month',
    int limit = 40,
  }) async {
    return dashboard;
  }

  @override
  Future<Map<String, dynamic>> getCaptainProfile() async {
    return profile;
  }

  @override
  Future<Map<String, dynamic>> getCaptainSubscription() async {
    return subscription;
  }

  @override
  Future<Map<String, dynamic>> upsertCaptainPresence({
    required bool isOnline,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
    int radiusM = 4000,
  }) async {
    return {'nearbyRequests': nearbyRequests};
  }

  @override
  Future<Map<String, dynamic>> acceptCustomerFare({required int rideId}) async {
    acceptedCustomerFareRideIds.add(rideId);
    currentRideEnvelope = {
      'ride': {
        'id': rideId,
        'status': 'captain_assigned',
        'assignedCaptainUserId': 42,
        'customerUserId': 7,
        'pickup': {
          'latitude': 33.31456,
          'longitude': 44.36611,
          'label': 'Bismayah Gate',
        },
        'dropoff': {
          'latitude': 33.32091,
          'longitude': 44.39118,
          'label': 'Central Mall',
        },
        'proposedFareIqd': 15000,
        'agreedFareIqd': 15000,
        'captain': {
          'fullName': 'Captain Noor',
          'phone': '07711111111',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'plateNumber': 'TX-001',
          'carColor': 'Silver',
        },
      },
      'bids': const <Map<String, dynamic>>[],
    };
    return currentRideEnvelope!;
  }

  @override
  Future<Map<String, dynamic>> declineRideRequest({required int rideId}) async {
    return {'rideId': rideId, 'declined': true};
  }

  @override
  Stream<TaxiLiveEvent> streamEvents({int? lastEventId}) {
    return streamController.stream;
  }

  void dispose() {
    streamController.close();
  }
}

class _FakeTaxiRouteService extends TaxiRouteService {
  _FakeTaxiRouteService() : super(dio: Dio());

  @override
  Future<TaxiRoutePreview> fetchDrivingRoutePreview({
    required LatLng from,
    required LatLng to,
  }) async {
    return TaxiRoutePreview(
      points: [from, to],
      distanceMeters: 1800,
      durationSeconds: 480,
    );
  }
}

UserModel _captainUser() {
  return UserModel(
    id: 42,
    fullName: 'Taxi Captain Test',
    phone: '07800000000',
    role: 'taxi_captain',
    block: 'B1',
    buildingNumber: '10',
    apartment: '2',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'en',
    isSuperAdmin: false,
  );
}

Map<String, dynamic> _nearbyRequest() {
  return {
    'id': 101,
    'pickup': {
      'label': 'Bismayah Gate',
      'latitude': 33.31456,
      'longitude': 44.36611,
    },
    'dropoff': {
      'label': 'Central Mall',
      'latitude': 33.32091,
      'longitude': 44.39118,
    },
    'proposedFareIqd': 15000,
    'customerNote': 'Need a quiet ride',
    'currentBidId': null,
    'myBid': null,
  };
}

Future<void> _pumpScreen(WidgetTester tester, _FakeTaxiApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(token: 'token', user: _captainUser()),
          ),
        ),
        taxiCaptainApiProvider.overrideWithValue(api),
        taxiCaptainRouteServiceProvider.overrideWithValue(
          _FakeTaxiRouteService(),
        ),
        locationPermissionServiceProvider.overrideWithValue(
          const _FakeLocationPermissionService(),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TaxiCaptainDashboardScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  final geolocatorPosition = Position(
    latitude: 33.31456,
    longitude: 44.36611,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: true,
  );
  late final GeolocatorPlatform previousGeolocatorPlatform;

  setUpAll(() {
    previousGeolocatorPlatform = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(geolocatorPosition);
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    GeolocatorPlatform.instance = previousGeolocatorPlatform;
  });

  testWidgets('session recovery keeps the active ride and re-syncs it', (
    tester,
  ) async {
    final api = _FakeTaxiApi(
      nearbyRequests: [_nearbyRequest()],
      dashboard: {
        'metrics': {
          'day': {'ridesCount': 0},
        },
      },
      profile: {
        'profile': {
          'id': 42,
          'fullName': 'Taxi Captain Test',
          'phone': '07800000000',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'carColor': 'Silver',
          'plateNumber': 'TX-001',
          'vehicleType': 'sedan',
          'isActive': true,
          'taxiAccountApproved': true,
          'ratingAvg': 4.8,
          'ridesCount': 12,
        },
      },
      subscription: {
        'subscription': {
          'canAccess': true,
          'phase': 'trial',
          'monthlyFeeIqd': 10000,
          'discountedMonthlyFeeIqd': 0,
        },
      },
    );
    // The captain is mid-ride when the session is silently recovered.
    api.currentRideEnvelope = {
      'ride': {
        'id': 555,
        'status': 'captain_assigned',
        'assignedCaptainUserId': 42,
        'customerUserId': 7,
        'pickup': {
          'latitude': 33.31456,
          'longitude': 44.36611,
          'label': 'Bismayah Gate',
        },
        'dropoff': {
          'latitude': 33.32091,
          'longitude': 44.39118,
          'label': 'Central Mall',
        },
        'proposedFareIqd': 15000,
        'agreedFareIqd': 15000,
        'captain': {
          'fullName': 'Captain Noor',
          'phone': '07711111111',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'plateNumber': 'TX-001',
          'carColor': 'Silver',
        },
      },
      'bids': const <Map<String, dynamic>>[],
    };

    await _pumpScreen(tester, api);

    // An active ride suppresses new request cards.
    expect(find.text('Accept customer fare'), findsNothing);
    final callsBeforeRecovery = api.currentRideCalls;

    SessionRecoveryBus.instance.requestRecovery();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Recovery must not drop the captain out of the ride, and must not start
    // surfacing new requests while that ride is still active.
    expect(tester.takeException(), isNull);
    expect(find.text('Accept customer fare'), findsNothing);
    expect(
      api.currentRideCalls,
      greaterThan(callsBeforeRecovery),
      reason: 'recovery must re-sync the current ride in the background',
    );
  });

  testWidgets('captain request card exposes accept customer fare action', (
    tester,
  ) async {
    final api = _FakeTaxiApi(
      nearbyRequests: [_nearbyRequest()],
      dashboard: {
        'metrics': {
          'day': {'ridesCount': 0},
        },
      },
      profile: {
        'profile': {
          'id': 42,
          'fullName': 'Taxi Captain Test',
          'phone': '07800000000',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'carColor': 'Silver',
          'plateNumber': 'TX-001',
          'vehicleType': 'sedan',
          'isActive': true,
          'deliveryAccountApproved': true,
          'ratingAvg': 4.8,
          'ridesCount': 12,
        },
      },
      subscription: {
        'subscription': {
          'canAccess': true,
          'phase': 'trial',
          'monthlyFeeIqd': 10000,
          'discountedMonthlyFeeIqd': 0,
        },
      },
    );

    await _pumpScreen(tester, api);

    expect(tester.takeException(), isNull);
    expect(find.text('Accept customer fare'), findsOneWidget);
    expect(find.textContaining('Customer fare'), findsWidgets);
    await tester.tap(find.text('Accept customer fare'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.acceptedCustomerFareRideIds, [101]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'captain app bar exposes competitions and notifications actions',
    (tester) async {
      final api = _FakeTaxiApi(
        nearbyRequests: [_nearbyRequest()],
        dashboard: {
          'metrics': {
            'day': {'ridesCount': 0},
          },
        },
        profile: {
          'profile': {
            'id': 42,
            'fullName': 'Taxi Captain Test',
            'phone': '07800000000',
            'carMake': 'Toyota',
            'carModel': 'Corolla',
            'carYear': 2022,
            'carColor': 'Silver',
            'plateNumber': 'TX-001',
            'vehicleType': 'sedan',
            'isActive': true,
            'deliveryAccountApproved': true,
            'ratingAvg': 4.8,
            'ridesCount': 12,
          },
        },
        subscription: {
          'subscription': {
            'canAccess': true,
            'phase': 'trial',
            'monthlyFeeIqd': 10000,
            'discountedMonthlyFeeIqd': 0,
          },
        },
      );

      addTearDown(api.dispose);
      await _pumpScreen(tester, api);

      expect(find.byIcon(Icons.emoji_events_outlined), findsWidgets);
      expect(find.byIcon(Icons.notifications_active_outlined), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('captain realtime ride request shows a visible snack', (
    tester,
  ) async {
    final streamController = StreamController<TaxiLiveEvent>.broadcast();
    final api = _FakeTaxiApi(
      nearbyRequests: [_nearbyRequest()],
      dashboard: {
        'metrics': {
          'day': {'ridesCount': 0},
        },
      },
      profile: {
        'profile': {
          'id': 42,
          'fullName': 'Taxi Captain Test',
          'phone': '07800000000',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'carColor': 'Silver',
          'plateNumber': 'TX-001',
          'vehicleType': 'sedan',
          'isActive': true,
          'deliveryAccountApproved': true,
          'ratingAvg': 4.8,
          'ridesCount': 12,
        },
      },
      subscription: {
        'subscription': {
          'canAccess': true,
          'phase': 'trial',
          'monthlyFeeIqd': 10000,
          'discountedMonthlyFeeIqd': 0,
        },
      },
      streamController: streamController,
    );

    addTearDown(api.dispose);
    await _pumpScreen(tester, api);

    streamController.add(
      const TaxiLiveEvent(
        event: 'taxi_ride_requested',
        data: {'rideId': 101},
        eventId: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('New taxi request arrived'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _FakeHttpClientRequest();
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  bool bufferOutput = false;

  @override
  int contentLength = 0;

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  int maxRedirects = 5;

  @override
  String method = 'GET';

  @override
  bool persistentConnection = false;

  @override
  Uri uri = Uri.parse('https://example.com');

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  void write(Object? object) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  static final List<int> _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5nX0cAAAAASUVORK5CYII=',
  );

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  String get reasonPhrase => 'OK';

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  Future<Socket> detachSocket() {
    throw UnsupportedError('detachSocket is not used in tests');
  }

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) {
    throw UnsupportedError('redirect is not used in tests');
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add('$value');
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = <String>['$value'];
  }

  @override
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.join(',');
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
