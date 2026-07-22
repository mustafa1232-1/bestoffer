import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';
import 'package:maslaki/features/tracking/ui/delivery_live_tracking_screen.dart';
import 'package:maslaki/features/tracking/ui/taxi_live_tracking_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:maslaki/pages/map_page.dart';

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
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add('$value');
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi(this.snapshot) : super(Dio());

  final Map<String, dynamic> snapshot;

  @override
  Future<Map<String, dynamic>> getTrackingSnapshot(int orderId) async =>
      snapshot;

  @override
  Future<Map<String, dynamic>> getPublicTrackingByToken(String token) async {
    return snapshot;
  }

  @override
  Stream<OrderTrackingLiveEvent> streamTrackingEvents({
    required int orderId,
    int? lastEventId,
  }) async* {}

  @override
  Stream<OrderTrackingLiveEvent> streamPublicTrackingByToken(
    String token,
  ) async* {}
}

class _ForbiddenOrdersApi extends OrdersApi {
  _ForbiddenOrdersApi() : super(Dio());

  DioException _forbidden() => DioException(
    requestOptions: RequestOptions(path: '/api/orders/7/tracking'),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/orders/7/tracking'),
      statusCode: 403,
      data: const {'message': 'FORBIDDEN_ORDER_TRACKING'},
    ),
    type: DioExceptionType.badResponse,
  );

  @override
  Future<Map<String, dynamic>> getTrackingSnapshot(int orderId) async =>
      throw _forbidden();

  @override
  Future<Map<String, dynamic>> getPublicTrackingByToken(String token) async =>
      throw _forbidden();

  @override
  Stream<OrderTrackingLiveEvent> streamTrackingEvents({
    required int orderId,
    int? lastEventId,
  }) async* {}

  @override
  Stream<OrderTrackingLiveEvent> streamPublicTrackingByToken(
    String token,
  ) async* {}
}

class _FakeTaxiApi extends TaxiApi {
  _FakeTaxiApi(this.envelope, {this.streamController, this.currentRideEnvelope})
    : super(Dio());

  final Map<String, dynamic> envelope;
  final StreamController<TaxiLiveEvent>? streamController;
  final Map<String, dynamic>? currentRideEnvelope;
  int rideDetailsCalls = 0;
  int currentRideCalls = 0;
  int sharedRideTrackCalls = 0;

  @override
  Future<Map<String, dynamic>?> getCurrentRideForCustomer() async {
    currentRideCalls += 1;
    return currentRideEnvelope;
  }

  @override
  Future<Map<String, dynamic>> getRideDetails(int rideId) async {
    rideDetailsCalls += 1;
    return envelope;
  }

  @override
  Future<Map<String, dynamic>> getSharedRideTrack({required int rideId}) async {
    sharedRideTrackCalls += 1;
    return envelope;
  }

  @override
  Future<Map<String, dynamic>> publicTrackByToken(String token) async {
    return envelope;
  }

  @override
  Stream<TaxiLiveEvent> streamRideEvents({
    required int rideId,
    int? lastEventId,
  }) => streamController?.stream ?? const Stream<TaxiLiveEvent>.empty();

  @override
  Stream<TaxiLiveEvent> streamPublicTrackByToken(String token) async* {}

  @override
  Future<List<Map<String, dynamic>>> listSavedPlaces() async => const [];

  @override
  Future<List<Map<String, dynamic>>> listFavoriteTrips() async => const [];

  @override
  Future<List<Map<String, dynamic>>> listNearbyCaptains({
    required double latitude,
    required double longitude,
    int radiusM = 3500,
    int limit = 60,
  }) async => const [];
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
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
      distanceMeters: 1820,
      durationSeconds: 480,
    );
  }
}

UserModel _customerUser() {
  return UserModel(
    id: 7,
    fullName: 'Customer User',
    phone: '07700000000',
    role: 'customer',
    block: 'A1',
    buildingNumber: '10',
    apartment: '2',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'en',
    isSuperAdmin: false,
  );
}

Map<String, dynamic> _assignedTaxiEnvelope({
  String status = 'captain_assigned',
  Map<String, dynamic>? latestLocation,
}) {
  final envelope = <String, dynamic>{
    'ride': <String, dynamic>{
      'id': 77,
      'status': status,
      'captain': <String, dynamic>{
        'id': 88,
        'fullName': 'Captain Noor',
        'phone': '07711111111',
        'profileImageUrl': 'https://example.com/captain.jpg',
        'ratingAvg': 4.8,
        'ratingCount': 128,
        'ridesCount': 321,
        'carMake': 'Toyota',
        'carModel': 'Corolla',
        'carYear': 2022,
        'carColor': 'White',
        'vehicleType': 'sedan',
        'plateNumber': 'TX-001',
        'carImageUrl': 'https://example.com/vehicle.jpg',
      },
      'pickup': <String, dynamic>{
        'latitude': 33.3128,
        'longitude': 44.3615,
        'label': 'Bismayah Gate',
      },
      'dropoff': <String, dynamic>{
        'latitude': 33.3201,
        'longitude': 44.3750,
        'label': 'Central Mall',
      },
      'customerFare': 14500,
      'finalFare': 16000,
      'captainName': 'Captain Noor',
      'captainPhotoUrl': 'https://example.com/captain.jpg',
      'captainPhone': '07711111111',
      'captainRating': 4.8,
      'captainRatingCount': 128,
      'captainCompletedTrips': 321,
      'captainLatitude': 33.3152,
      'captainLongitude': 44.3648,
      'captainHeading': 82,
      'captainDistanceMeters': 640,
      'captainEstimatedArrivalMinutes': 4,
      'vehicle': <String, dynamic>{
        'vehicleId': 9,
        'vehicleMake': 'Toyota',
        'vehicleModel': 'Corolla',
        'vehicleYear': 2022,
        'vehicleColor': 'White',
        'vehicleType': 'sedan',
        'vehiclePlate': 'TX-001',
        'vehicleNumber': 'TX-001',
        'vehicleImage': 'https://example.com/vehicle.jpg',
      },
      if (status == 'ride_started')
        'latestLocation': <String, dynamic>{
          'latitude': 33.3181,
          'longitude': 44.3701,
          'updatedAt': '2026-07-13T10:00:00Z',
        },
    },
  };
  if (latestLocation != null) {
    envelope['latestLocation'] = latestLocation;
  }
  return envelope;
}

Map<String, dynamic> _assignedDeliverySnapshot() {
  return <String, dynamic>{
    'stage': 'heading_to_customer',
    'lastUpdatedAt': '2026-07-13T10:05:00Z',
    'latestLocation': <String, dynamic>{
      'latitude': 33.3181,
      'longitude': 44.3701,
      'updatedAt': '2026-07-13T10:05:00Z',
    },
    'destination': <String, dynamic>{
      'latitude': 33.3201,
      'longitude': 44.3750,
      'label': 'Central Mall',
    },
    'merchant': <String, dynamic>{'name': 'Merchant One'},
    'courier': <String, dynamic>{
      'userId': 86,
      'fullName': 'Courier Noor',
      'phone': '07711111111',
      'availabilityStatus': 'on_the_way',
    },
    'deliveryAssignment': <String, dynamic>{
      'assignmentStatus': 'ASSIGNED',
      'driver': <String, dynamic>{
        'id': 86,
        'name': 'Courier Noor',
        'photoUrl': 'https://example.com/courier.jpg',
        'phone': '07711111111',
        'rating': 4.7,
      },
    },
    'order': <String, dynamic>{
      'id': 41,
      'status': 'on_the_way',
      'merchantName': 'Merchant One',
      'totalAmount': 12500,
      'customerCity': 'Basmaya',
      'customerBlock': 'A1',
      'customerBuildingNumber': '12',
    },
  };
}

Widget _wrapForTest(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

Future<void> _setTallSurface(
  WidgetTester tester, {
  Size size = const Size(1080, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _scrollTaxiActionsIntoView(WidgetTester tester) async {
  final scrollable = find.byType(ListView).evaluate().isNotEmpty
      ? find.byType(ListView).last
      : find.byType(Scrollable).last;
  for (var i = 0; i < 4; i++) {
    await tester.drag(scrollable, const Offset(0, -560));
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text('Message captain').evaluate().isNotEmpty ||
        find.text('Ride details').evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _expectTerminalTaxiRideReturnsHomeOnce(
  WidgetTester tester, {
  required String status,
  Size size = const Size(1080, 2400),
}) async {
  await _setTallSurface(tester, size: size);
  final api = _FakeTaxiApi(
    _assignedTaxiEnvelope(status: status),
    currentRideEnvelope: null,
  );

  await tester.pumpWidget(
    _wrapForTest(
      TaxiLiveTrackingScreen(
        rideId: 77,
        initialEnvelope: _assignedTaxiEnvelope(status: status),
      ),
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(token: 'token', user: _customerUser()),
          ),
        ),
        taxiApiProvider.overrideWithValue(api),
        taxiRouteServiceProvider.overrideWithValue(_FakeTaxiRouteService()),
      ],
    ),
  );

  await tester.pump();
  for (var i = 0; i < 20 && find.byType(MapPage).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  expect(tester.takeException(), isNull);
  expect(find.byType(MapPage), findsOneWidget);
  expect(find.byType(TaxiLiveTrackingScreen), findsNothing);
  expect(api.rideDetailsCalls, 1);
  expect(api.currentRideCalls, 1);
  expect(api.sharedRideTrackCalls, 0);

  await tester.binding.handlePopRoute();
  await tester.pump();
  expect(find.byType(TaxiLiveTrackingScreen), findsNothing);

  await tester.pump(const Duration(seconds: 60));
  expect(tester.takeException(), isNull);
  expect(api.rideDetailsCalls, 1);
  expect(api.currentRideCalls, 1);
  expect(api.sharedRideTrackCalls, 0);
}

Future<void> _expectTerminalTaxiRideKeepsMapAboveShellRoot(
  WidgetTester tester, {
  required Size size,
}) async {
  await _setTallSurface(tester, size: size);
  final navigatorKey = GlobalKey<NavigatorState>();
  final api = _FakeTaxiApi(
    _assignedTaxiEnvelope(status: 'completed'),
    currentRideEnvelope: null,
  );

  await tester.pumpWidget(
    _wrapForTest(
      Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Shell root')),
        ),
      ),
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(token: 'token', user: _customerUser()),
          ),
        ),
        taxiApiProvider.overrideWithValue(api),
        taxiRouteServiceProvider.overrideWithValue(_FakeTaxiRouteService()),
      ],
    ),
  );

  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => TaxiLiveTrackingScreen(
        rideId: 77,
        initialEnvelope: _assignedTaxiEnvelope(status: 'completed'),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20 && find.byType(MapPage).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  expect(tester.takeException(), isNull);
  expect(find.byType(MapPage), findsOneWidget);
  expect(find.text('Shell root'), findsNothing);
  expect(find.byType(TaxiLiveTrackingScreen), findsNothing);
  expect(navigatorKey.currentState!.canPop(), isTrue);
  expect(api.rideDetailsCalls, 1);
  expect(api.currentRideCalls, 1);
}

void main() {
  late HttpOverrides? previousOverrides;

  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });

  testWidgets('delivery tracking survives malformed tracking payloads', (
    tester,
  ) async {
    await _setTallSurface(tester);
    final api = _FakeOrdersApi(<String, dynamic>{
      'stage': 'heading_to_customer',
      'merchant': 'bad-merchant-shape',
      'courier': 'bad-courier-shape',
      'latestLocation': 'bad-location-shape',
      'destination': 'bad-destination-shape',
      'order': <String, dynamic>{
        'id': 41,
        'totalAmount': null,
        'merchantName': null,
      },
    });

    await tester.pumpWidget(
      _wrapForTest(
        const DeliveryLiveTrackingScreen(orderId: 41),
        overrides: [ordersApiProvider.overrideWithValue(api)],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Live Order Tracking'), findsOneWidget);
    expect(find.text('Merchant'), findsOneWidget);
    expect(find.text('Awaiting assignment'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Chat'), findsNothing);
    expect(find.byTooltip('Call'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
  });

  testWidgets('delivery tracking shows assigned courier actions and data', (
    tester,
  ) async {
    await _setTallSurface(tester);
    final api = _FakeOrdersApi(_assignedDeliverySnapshot());

    await tester.pumpWidget(
      _wrapForTest(
        const DeliveryLiveTrackingScreen(orderId: 41),
        overrides: [ordersApiProvider.overrideWithValue(api)],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Live Order Tracking'), findsOneWidget);
    expect(find.text('Courier Noor'), findsWidgets);
    expect(find.text('Central Mall'), findsWidgets);
    expect(find.byTooltip('Chat'), findsOneWidget);
    expect(find.byTooltip('Call'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
  });

  testWidgets('taxi tracking survives malformed ride payloads', (tester) async {
    await _setTallSurface(tester);
    final api = _FakeTaxiApi(<String, dynamic>{
      'events': 'bad-events-shape',
      'latestLocation': 'bad-location-shape',
      'ride': <String, dynamic>{
        'id': 77,
        'status': 'captain_assigned',
        'captain': 'bad-captain-shape',
        'pickup': 'bad-pickup-shape',
        'dropoff': <String, dynamic>{},
        'agreedFareIqd': null,
        'proposedFareIqd': null,
      },
    });

    await tester.pumpWidget(
      _wrapForTest(
        TaxiLiveTrackingScreen(rideId: 77, initialEnvelope: api.envelope),
        overrides: [taxiApiProvider.overrideWithValue(api)],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Taxi Live Tracking'), findsOneWidget);
    expect(find.text('Captain is heading to pickup'), findsOneWidget);
    expect(find.text('Not available'), findsAtLeastNWidgets(1));
  });

  testWidgets('taxi tracking shows searching state without chat actions', (
    tester,
  ) async {
    await _setTallSurface(tester);
    final api = _FakeTaxiApi(<String, dynamic>{
      'events': const <String, dynamic>{},
      'ride': <String, dynamic>{
        'id': 78,
        'status': 'searching',
        'pickup': <String, dynamic>{
          'latitude': 33.3128,
          'longitude': 44.3615,
          'label': 'Bismayah Gate',
        },
        'dropoff': <String, dynamic>{
          'latitude': 33.3201,
          'longitude': 44.3750,
          'label': 'Central Mall',
        },
        'proposedFareIqd': null,
        'agreedFareIqd': null,
        'captain': null,
      },
    });

    await tester.pumpWidget(
      _wrapForTest(
        TaxiLiveTrackingScreen(rideId: 78, initialEnvelope: api.envelope),
        overrides: [taxiApiProvider.overrideWithValue(api)],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Searching for a captain'), findsOneWidget);
    expect(find.text('Not available'), findsAtLeastNWidgets(1));
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Call'), findsNothing);
  });

  testWidgets('taxi tracking shows the assigned ride card with captain data', (
    tester,
  ) async {
    await _setTallSurface(tester);
    await tester.pumpWidget(
      _wrapForTest(
        TaxiLiveTrackingScreen(
          rideId: 77,
          initialEnvelope: _assignedTaxiEnvelope(status: 'captain_assigned'),
        ),
        overrides: [
          taxiApiProvider.overrideWithValue(
            _FakeTaxiApi(_assignedTaxiEnvelope()),
          ),
        ],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Taxi Live Tracking'), findsOneWidget);
    expect(find.text('Captain is heading to pickup'), findsOneWidget);
    expect(find.text('Captain Noor'), findsWidgets);
    expect(find.textContaining('Toyota'), findsWidgets);
    expect(find.textContaining('TX-001'), findsWidgets);
    await _scrollTaxiActionsIntoView(tester);
    expect(find.text('Message captain'), findsOneWidget);
    expect(find.text('Ride details'), findsOneWidget);
    expect(find.text('Share ride'), findsOneWidget);
    expect(find.text('Cancel ride'), findsOneWidget);
  });

  testWidgets('taxi tracking returns to home once after a completed ride', (
    tester,
  ) async {
    await _expectTerminalTaxiRideReturnsHomeOnce(tester, status: 'completed');
  });

  for (final entry in <MapEntry<String, Size>>[
    const MapEntry('360x640', Size(360, 640)),
    const MapEntry('393x852', Size(393, 852)),
    const MapEntry('412x915', Size(412, 915)),
  ]) {
    testWidgets(
      'taxi terminal return keeps fullscreen map route above shell stack at ${entry.key}',
      (tester) async {
        await _expectTerminalTaxiRideKeepsMapAboveShellRoot(
          tester,
          size: entry.value,
        );
      },
    );
  }

  testWidgets(
    'taxi tracking returns to home once after a customer-cancelled ride',
    (tester) async {
      await _expectTerminalTaxiRideReturnsHomeOnce(
        tester,
        status: 'cancelled_by_customer',
      );
    },
  );

  testWidgets(
    'taxi tracking returns to home once after a captain-cancelled ride',
    (tester) async {
      await _expectTerminalTaxiRideReturnsHomeOnce(
        tester,
        status: 'cancelled_by_captain',
      );
    },
  );

  testWidgets(
    'taxi tracking returns to home once after an admin-cancelled ride',
    (tester) async {
      await _expectTerminalTaxiRideReturnsHomeOnce(
        tester,
        status: 'cancelled_by_admin',
      );
    },
  );

  testWidgets('taxi tracking returns to home once after an expired ride', (
    tester,
  ) async {
    await _expectTerminalTaxiRideReturnsHomeOnce(tester, status: 'expired');
  });

  testWidgets(
    'taxi tracking preserves captain and vehicle snapshot after location updates',
    (tester) async {
      await _setTallSurface(tester);
      final events = StreamController<TaxiLiveEvent>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(
        _wrapForTest(
          TaxiLiveTrackingScreen(
            rideId: 77,
            initialEnvelope: _assignedTaxiEnvelope(status: 'captain_assigned'),
          ),
          overrides: [
            taxiApiProvider.overrideWithValue(
              _FakeTaxiApi(_assignedTaxiEnvelope(), streamController: events),
            ),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Captain Noor'), findsWidgets);
      expect(find.textContaining('Toyota'), findsWidgets);

      events.add(
        const TaxiLiveEvent(
          event: 'taxi_location_update',
          data: <String, dynamic>{
            'rideId': 77,
            'ride': <String, dynamic>{'id': 77, 'status': 'captain_assigned'},
            'location': <String, dynamic>{
              'latitude': 33.3169,
              'longitude': 44.3671,
              'updatedAt': '2026-07-13T10:01:00Z',
            },
          },
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Captain Noor'), findsWidgets);
      expect(find.textContaining('Toyota'), findsWidgets);
      await _scrollTaxiActionsIntoView(tester);
      expect(find.text('Cancel ride'), findsOneWidget);
    },
  );

  testWidgets(
    'taxi tracking only exposes cancel on cancellable active states',
    (tester) async {
      await _setTallSurface(tester);
      await tester.pumpWidget(
        _wrapForTest(
          TaxiLiveTrackingScreen(
            rideId: 77,
            initialEnvelope: _assignedTaxiEnvelope(status: 'captain_assigned'),
          ),
          overrides: [
            taxiApiProvider.overrideWithValue(
              _FakeTaxiApi(_assignedTaxiEnvelope(status: 'captain_assigned')),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('Cancel ride'),
        200.0,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Cancel ride'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _wrapForTest(
          TaxiLiveTrackingScreen(
            rideId: 77,
            initialEnvelope: _assignedTaxiEnvelope(status: 'ride_started'),
          ),
          overrides: [
            taxiApiProvider.overrideWithValue(
              _FakeTaxiApi(_assignedTaxiEnvelope(status: 'ride_started')),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _scrollTaxiActionsIntoView(tester);
      expect(find.text('Cancel ride'), findsNothing);
      expect(find.text('Message captain'), findsOneWidget);
      expect(find.text('Ride details'), findsOneWidget);
      expect(find.text('Share ride'), findsOneWidget);
    },
  );

  testWidgets(
    'taxi tracking shows terminal summary and no active actions for completed rides',
    (tester) async {
      await _setTallSurface(tester);
      await tester.pumpWidget(
        _wrapForTest(
          TaxiLiveTrackingScreen(
            rideId: 77,
            sharedReadonly: true,
            initialEnvelope: _assignedTaxiEnvelope(status: 'completed'),
          ),
          overrides: [
            taxiApiProvider.overrideWithValue(
              _FakeTaxiApi(_assignedTaxiEnvelope(status: 'completed')),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ride completed successfully'), findsWidgets);
      expect(find.text('Cancel ride'), findsNothing);
      expect(find.text('Message captain'), findsNothing);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Share ride'), findsNothing);
    },
  );

  testWidgets(
    'map page skipInitialBootstrap still performs auth and current ride resync',
    (tester) async {
      await _setTallSurface(tester);
      final api = _FakeTaxiApi(
        _assignedTaxiEnvelope(status: 'completed'),
        currentRideEnvelope: null,
      );

      await tester.pumpWidget(
        _wrapForTest(
          const MapPage(skipInitialBootstrap: true),
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(
                ref,
                AuthState(token: 'token', user: _customerUser()),
              ),
            ),
            taxiApiProvider.overrideWithValue(api),
            taxiRouteServiceProvider.overrideWithValue(_FakeTaxiRouteService()),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(api.currentRideCalls, 1);
      final l10n = AppLocalizations.of(tester.element(find.byType(MapPage)));
      expect(find.text(l10n.mapPageTitle), findsOneWidget);
      expect(find.text(l10n.mapPageCurrentLocation), findsWidgets);
    },
  );

  testWidgets('delivery tracking shows a graceful 403 state with retry', (
    tester,
  ) async {
    await _setTallSurface(tester);
    await tester.pumpWidget(
      _wrapForTest(
        const DeliveryLiveTrackingScreen(orderId: 7),
        overrides: [ordersApiProvider.overrideWithValue(_ForbiddenOrdersApi())],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(
      find.text('You do not have permission to track this order.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
