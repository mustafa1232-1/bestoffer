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

class _FakeTaxiApi extends TaxiApi {
  _FakeTaxiApi(this.envelope) : super(Dio());

  final Map<String, dynamic> envelope;

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
  }) async* {}

  @override
  Stream<TaxiLiveEvent> streamPublicTrackByToken(String token) async* {}
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
    expect(find.text('Awaiting assignment'), findsOneWidget);
  });

  testWidgets('taxi tracking survives malformed ride payloads', (tester) async {
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
        const TaxiLiveTrackingScreen(rideId: 77),
        overrides: [taxiApiProvider.overrideWithValue(api)],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Taxi Live Tracking'), findsOneWidget);
    expect(find.text('Awaiting assignment'), findsOneWidget);
  });
}
