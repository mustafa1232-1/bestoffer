import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:maslaki/pages/map_page.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
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

class _FakeTaxiApi extends TaxiApi {
  _FakeTaxiApi({this.currentRideEnvelope}) : super(Dio());

  final Map<String, dynamic>? currentRideEnvelope;

  @override
  Future<Map<String, dynamic>?> getCurrentRideForCustomer() async {
    return currentRideEnvelope;
  }

  @override
  Stream<TaxiLiveEvent> streamEvents({int? lastEventId}) async* {}
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
      distanceMeters: 1850,
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
    preferredLocale: 'ar',
    isSuperAdmin: false,
  );
}

Map<String, dynamic> _rideEnvelope({
  required String status,
  int? captainRating,
}) {
  final ride = <String, dynamic>{
    'id': 41,
    'status': status,
    'pickup': {
      'latitude': 33.3128,
      'longitude': 44.3615,
      'label': 'Bismayah Gate',
    },
    'dropoff': {
      'latitude': 33.3201,
      'longitude': 44.3750,
      'label': 'Central Mall',
    },
    'proposedFareIqd': 10000,
    'agreedFareIqd': status == 'completed' ? 12500 : null,
    'captainRating': captainRating,
    'captain': {
      'fullName': 'Captain Noor',
      'phone': '07711111111',
      'carMake': 'Toyota',
      'carModel': 'Corolla',
      'carYear': 2022,
      'plateNumber': 'BGD-123',
    },
  };

  if (status == 'searching') {
    ride['currentBidId'] = 11;
  }

  return <String, dynamic>{
    'ride': ride,
    'bids': status == 'searching'
        ? <Map<String, dynamic>>[
            {
              'id': 11,
              'status': 'active',
              'offeredFareIqd': 13500,
              'etaMinutes': 6,
              'counterOfferCount': 1,
              'captain': {'fullName': 'Captain Noor'},
            },
          ]
        : const <Map<String, dynamic>>[],
    'bidQueue': status == 'searching'
        ? <String, dynamic>{
            'currentBidId': 11,
            'queueSize': 1,
            'negotiationTimeoutSeconds': 180,
          }
        : null,
  };
}

Future<void> _pumpMapPage(
  WidgetTester tester, {
  Map<String, dynamic>? currentRideEnvelope,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(token: 'token', user: _customerUser()),
          ),
        ),
        taxiApiProvider.overrideWithValue(
          _FakeTaxiApi(currentRideEnvelope: currentRideEnvelope),
        ),
        taxiRouteServiceProvider.overrideWithValue(_FakeTaxiRouteService()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MapPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets(
    'map page initializes without inherited-widget crash and seeds pickup label',
    (tester) async {
      await _pumpMapPage(tester);

      expect(tester.takeException(), isNull);

      final l10n = AppLocalizations.of(tester.element(find.byType(MapPage)));
      expect(find.text(l10n.mapPageTitle), findsOneWidget);
      expect(find.text(l10n.mapPageCurrentLocation), findsWidgets);
    },
  );

  testWidgets('map page shows the searching ride shell without crashing', (
    tester,
  ) async {
    await _pumpMapPage(
      tester,
      currentRideEnvelope: _rideEnvelope(status: 'searching'),
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(MapPage)));

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.mapPageRideSearchingTitle), findsOneWidget);
    expect(find.text(l10n.mapPageNegotiationTitle), findsOneWidget);
  });

  testWidgets('completed ride shows the localized rating call to action', (
    tester,
  ) async {
    await _pumpMapPage(
      tester,
      currentRideEnvelope: _rideEnvelope(status: 'completed'),
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(MapPage)));

    expect(find.text(l10n.mapPageRideCompletedTitle), findsOneWidget);
    expect(find.text(l10n.mapPageRateTaxiRide), findsOneWidget);
  });
}
