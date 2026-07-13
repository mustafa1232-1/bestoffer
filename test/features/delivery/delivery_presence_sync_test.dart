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
  _FakeDeliveryApi() : super(Dio());

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

  final List<Map<String, dynamic>> presencePayloads = [];

  @override
  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
  }) async {
    ordersCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> analytics() async {
    analyticsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    dashboardCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    reportsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<List<dynamic>> requestsV2({int limit = 40, int offset = 0}) async {
    requestsCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> competitionsV2({String scope = 'active'}) async {
    if (scope == 'history') {
      historyCompetitionsCalls += 1;
    } else {
      activeCompetitionsCalls += 1;
    }
    return const <String, dynamic>{'competitions': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionProgressV2() async {
    competitionProgressCalls += 1;
    return const <String, dynamic>{'items': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionAchievementsSummaryV2() async {
    achievementsCalls += 1;
    return const <String, dynamic>{'summary': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> endDayReadiness() async {
    readinessCalls += 1;
    return const {'canEndDay': true, 'openSettlements': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> upsertPresence({
    required double latitude,
    required double longitude,
    int? orderId,
    bool isOnline = true,
    double? headingDeg,
    double? speedKmh,
    double? accuracyM,
  }) async {
    presencePayloads.add(<String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'orderId': orderId,
      'isOnline': isOnline,
      'headingDeg': headingDeg,
      'speedKmh': speedKmh,
      'accuracyM': accuracyM,
    });
    return <String, dynamic>{
      'presence': <String, dynamic>{'courierUserId': 86, 'orderId': orderId},
    };
  }
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
    'delivery bootstrap publishes a general heartbeat when no active order exists',
    () async {
      final permissionStatus = await const _FakeLocationPermissionService()
          .getStatus();
      expect(permissionStatus.state, AppLocationPermissionState.grantedPrecise);
      final directPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      expect(directPosition.latitude, 33.31456);
      expect(directPosition.longitude, 44.36611);

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
      await container
          .read(deliveryControllerProvider.notifier)
          .syncCourierPresenceForTesting(
            skipPreconditions: true,
            apiOverride: api,
            positionOverride: geolocatorPosition,
            currentOrdersOverride: const <OrderModel>[],
          );

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
      expect(api.presencePayloads.single['latitude'], 33.31456);
      expect(api.presencePayloads.single['longitude'], 44.36611);
    },
  );
}
