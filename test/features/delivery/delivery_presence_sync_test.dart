import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:core_maps/core_maps.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/orders/models/order_model.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
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

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi() : super(Dio()) {
    dio.options.baseUrl = 'https://bestoffer-production.up.railway.app';
  }

  int ordersCalls = 0;
  int analyticsCalls = 0;
  int dashboardCalls = 0;
  int reportsCalls = 0;
  int requestsCalls = 0;
  int activeCompetitionsCalls = 0;
  int historyCompetitionsCalls = 0;
  int competitionProgressCalls = 0;
  int achievementsCalls = 0;
  int readinessCalls = 0;
  bool failPresence = false;
  int failPresenceStatusCode = 503;

  final List<Map<String, dynamic>> presencePayloads = [];

  @override
  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    ordersCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> analytics({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    analyticsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    dashboardCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    reportsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<List<dynamic>> requestsV2({
    int limit = 40,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    requestsCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> competitionsV2({
    String scope = 'active',
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (scope == 'history') {
      historyCompetitionsCalls += 1;
    } else {
      activeCompetitionsCalls += 1;
    }
    return const <String, dynamic>{'competitions': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionProgressV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    competitionProgressCalls += 1;
    return const <String, dynamic>{'items': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionAchievementsSummaryV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    achievementsCalls += 1;
    return const <String, dynamic>{'summary': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> endDayReadiness({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    readinessCalls += 1;
    return const {'canEndDay': true, 'openSettlements': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> upsertPresence({
    double? latitude,
    double? longitude,
    int? orderId,
    bool isOnline = true,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (failPresence) {
      final requestOptions = RequestOptions(
        path: '/api/courier/presence',
        baseUrl: dio.options.baseUrl,
      );
      throw DioException(
        requestOptions: requestOptions,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions,
          statusCode: failPresenceStatusCode,
          data: <String, dynamic>{
            'code': 'PRESENCE_FAILED',
            'message': 'Presence failed',
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    presencePayloads.add(<String, dynamic>{
      'orderId': orderId,
      'isOnline': isOnline,
      ...?(latitude == null ? null : <String, dynamic>{'latitude': latitude}),
      ...?(longitude == null
          ? null
          : <String, dynamic>{'longitude': longitude}),
      ...?(headingDeg == null
          ? null
          : <String, dynamic>{'headingDeg': headingDeg}),
      ...?(speedKmh == null ? null : <String, dynamic>{'speedKmh': speedKmh}),
      ...?(accuracyM == null
          ? null
          : <String, dynamic>{'accuracyM': accuracyM}),
    });
    return <String, dynamic>{
      'presence': <String, dynamic>{'courierUserId': 86, 'orderId': orderId},
    };
  }
}

OrderModel _assignedOrder({required int id, String status = 'on_the_way'}) {
  return OrderModel.fromJson({
    'id': id,
    'merchant_id': 1,
    'customer_user_id': 2,
    'merchant_name': 'Merchant',
    'status': status,
    'customer_full_name': 'Customer',
    'customer_phone': '0770000000',
    'customer_city': 'Basmaya',
    'customer_block': 'A1',
    'customer_building_number': '12',
    'customer_apartment': '3',
    'delivery_user_id': 86,
    'delivery_assignment_status': 'ASSIGNED',
    'total_amount': 1000,
    'items': const <dynamic>[],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final previousGeolocator = GeolocatorPlatform.instance;
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

  setUp(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(geolocatorPosition);
  });

  tearDown(() {
    GeolocatorPlatform.instance = previousGeolocator;
  });

  test(
    'delivery bootstrap publishes an idle heartbeat without coordinates when no active order exists',
    () async {
      final api = _FakeDeliveryApi();
      final authState = AuthState(
        user: UserModel(
          id: 86,
          fullName: 'Delivery Driver',
          phone: '07711234567',
          role: 'delivery',
          block: 'A1',
          buildingNumber: '12',
          apartment: '3',
          imageUrl: null,
          workTitle: null,
          workCompany: null,
          preferredLocale: null,
          isSuperAdmin: false,
        ),
        token: 'delivery-token',
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, authState),
          ),
          deliveryApiProvider.overrideWithValue(api),
          locationPermissionServiceProvider.overrideWithValue(
            const _FakeLocationPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final auth = container.read(authControllerProvider);
      expect(auth.isAuthed, isTrue);
      expect(auth.isDelivery, isTrue);

      await container.read(deliveryControllerProvider.notifier).bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(deliveryControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(api.ordersCalls, 1);
      expect(api.analyticsCalls, 1);
      expect(api.dashboardCalls, 1);
      expect(api.reportsCalls, 1);
      expect(api.requestsCalls, 1);
      expect(api.activeCompetitionsCalls, 1);
      expect(api.historyCompetitionsCalls, 1);
      expect(api.competitionProgressCalls, 1);
      expect(api.achievementsCalls, 1);
      expect(api.readinessCalls, 1);
      expect(api.presencePayloads, hasLength(1));
      expect(api.presencePayloads.single['orderId'], isNull);
      expect(api.presencePayloads.single['isOnline'], isTrue);
      expect(api.presencePayloads.single.containsKey('latitude'), isFalse);
      expect(api.presencePayloads.single.containsKey('longitude'), isFalse);
      expect(
        state.presenceEndpointHost,
        'https://bestoffer-production.up.railway.app',
      );
      expect(state.presenceUserId, 86);
      expect(state.lastPresenceAttemptAt, isNotNull);
      expect(state.lastPresenceSuccessAt, isNotNull);
      expect(state.lastPresenceHttpStatus, 200);
      expect(state.lastPresenceError, isNull);
    },
  );

  test(
    'delivery presence heartbeat continues after live-order polling stops',
    () async {
      final api = _FakeDeliveryApi();
      final authState = AuthState(
        user: UserModel(
          id: 86,
          fullName: 'Delivery Driver',
          phone: '07711234567',
          role: 'delivery',
          block: 'A1',
          buildingNumber: '12',
          apartment: '3',
          imageUrl: null,
          workTitle: null,
          workCompany: null,
          preferredLocale: null,
          isSuperAdmin: false,
        ),
        token: 'delivery-token',
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, authState),
          ),
          deliveryApiProvider.overrideWithValue(api),
          locationPermissionServiceProvider.overrideWithValue(
            const _FakeLocationPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(deliveryControllerProvider.notifier);
      controller.startPresenceHeartbeat(
        interval: const Duration(milliseconds: 20),
      );

      await Future<void>.delayed(const Duration(milliseconds: 75));
      final beforeStop = api.presencePayloads.length;
      expect(beforeStop, greaterThan(0));

      controller.stopLiveOrders(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 75));

      expect(api.presencePayloads.length, greaterThan(beforeStop));
      controller.stopPresenceHeartbeat();
    },
  );

  test(
    'delivery resume forces another idle heartbeat without coordinates',
    () async {
      final api = _FakeDeliveryApi();
      final authState = AuthState(
        user: UserModel(
          id: 86,
          fullName: 'Delivery Driver',
          phone: '07711234567',
          role: 'delivery',
          block: 'A1',
          buildingNumber: '12',
          apartment: '3',
          imageUrl: null,
          workTitle: null,
          workCompany: null,
          preferredLocale: null,
          isSuperAdmin: false,
        ),
        token: 'delivery-token',
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, authState),
          ),
          deliveryApiProvider.overrideWithValue(api),
          locationPermissionServiceProvider.overrideWithValue(
            const _FakeLocationPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(deliveryControllerProvider.notifier);
      await controller.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(api.presencePayloads, hasLength(2));
      for (final payload in api.presencePayloads) {
        expect(payload['orderId'], isNull);
        expect(payload.containsKey('latitude'), isFalse);
        expect(payload.containsKey('longitude'), isFalse);
      }
      final state = container.read(deliveryControllerProvider);
      expect(state.lastPresenceSuccessAt, isNotNull);
      expect(state.lastPresenceHttpStatus, 200);
      expect(state.lastPresenceError, isNull);
    },
  );

  test(
    'delivery presence sync publishes coordinates for a trackable order and repeats on demand',
    () async {
      final api = _FakeDeliveryApi();
      final authState = AuthState(
        user: UserModel(
          id: 86,
          fullName: 'Delivery Driver',
          phone: '07711234567',
          role: 'delivery',
          block: 'A1',
          buildingNumber: '12',
          apartment: '3',
          imageUrl: null,
          workTitle: null,
          workCompany: null,
          preferredLocale: null,
          isSuperAdmin: false,
        ),
        token: 'delivery-token',
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, authState),
          ),
          deliveryApiProvider.overrideWithValue(api),
          locationPermissionServiceProvider.overrideWithValue(
            const _FakeLocationPermissionService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(deliveryControllerProvider.notifier)
          .syncCourierPresenceForTesting(
            skipPreconditions: true,
            apiOverride: api,
            positionOverride: geolocatorPosition,
            currentOrdersOverride: [_assignedOrder(id: 301)],
          );
      await container
          .read(deliveryControllerProvider.notifier)
          .syncCourierPresenceForTesting(
            force: true,
            skipPreconditions: true,
            apiOverride: api,
            positionOverride: geolocatorPosition,
            currentOrdersOverride: [_assignedOrder(id: 301)],
          );

      final state = container.read(deliveryControllerProvider);
      expect(api.presencePayloads, hasLength(2));
      for (final payload in api.presencePayloads) {
        expect(payload['orderId'], 301);
        expect(payload['isOnline'], isTrue);
        expect(payload['latitude'], 33.31456);
        expect(payload['longitude'], 44.36611);
      }
      expect(state.lastPresenceSuccessAt, isNotNull);
      expect(state.lastPresenceHttpStatus, 200);
      expect(state.lastPresenceError, isNull);
    },
  );

  test('delivery presence sync surfaces API errors in diagnostics', () async {
    final api = _FakeDeliveryApi()..failPresence = true;
    final authState = AuthState(
      user: UserModel(
        id: 86,
        fullName: 'Delivery Driver',
        phone: '07711234567',
        role: 'delivery',
        block: 'A1',
        buildingNumber: '12',
        apartment: '3',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: null,
        isSuperAdmin: false,
      ),
      token: 'delivery-token',
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, authState),
        ),
        deliveryApiProvider.overrideWithValue(api),
        locationPermissionServiceProvider.overrideWithValue(
          const _FakeLocationPermissionService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(deliveryControllerProvider.notifier)
          .syncCourierPresenceForTesting(
            skipPreconditions: true,
            apiOverride: api,
            currentOrdersOverride: const <OrderModel>[],
          ),
      throwsA(isA<DioException>()),
    );

    final state = container.read(deliveryControllerProvider);
    expect(state.lastPresenceAttemptAt, isNotNull);
    expect(state.lastPresenceSuccessAt, isNull);
    expect(state.lastPresenceHttpStatus, 503);
    expect(state.lastPresenceError, contains('Presence failed'));
  });
}
