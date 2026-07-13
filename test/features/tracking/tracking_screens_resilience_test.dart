import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/tracking/ui/delivery_live_tracking_screen.dart';
import 'package:maslaki/features/tracking/ui/taxi_live_tracking_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

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
  _FakeTaxiApi(this.envelope, {this.streamController}) : super(Dio());

  final Map<String, dynamic> envelope;
  final StreamController<TaxiLiveEvent>? streamController;

  @override
  Future<Map<String, dynamic>> getRideDetails(int rideId) async => envelope;

  @override
  Future<Map<String, dynamic>> getSharedRideTrack({required int rideId}) async {
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

Future<void> _setTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2400));
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
    expect(find.text('Cancel ride'), findsOneWidget);
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
