import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/features/owner/data/owner_api.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';

/// Records courier PATCH calls so we can assert the app never sends an invalid
/// courier id (e.g. 0 from a row with a missing user_id) to
/// PATCH /api/merchant/couriers/:id.
class _SpyOwnerApi extends OwnerApi {
  _SpyOwnerApi() : super(Dio());

  int patchCalls = 0;
  int? lastCourierUserId;
  int merchantUpdateCalls = 0;
  Map<String, dynamic>? lastMerchantUpdateBody;

  @override
  Future<Map<String, dynamic>> updateMerchant(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
    LocalImageFile? logoFile,
    LocalImageFile? coverFile,
  }) async {
    merchantUpdateCalls += 1;
    lastMerchantUpdateBody = Map<String, dynamic>.from(body);
    return {
      'merchant': {
        'id': 9,
        'name': 'Maslaki Store',
        'type': 'market',
        'activity_type': 'market',
        'is_open': body['isOpen'] == true,
        'is_approved': true,
        'approval_status': 'approved',
        'supports_chat': false,
        'supports_attachments': false,
        'supports_pharmacy_workflow': false,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> patchMerchantCourierV2({
    required int courierUserId,
    bool? isActive,
    String? availabilityStatus,
    String? vehicleType,
  }) async {
    patchCalls += 1;
    lastCourierUserId = courierUserId;
    return <String, dynamic>{};
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      user: UserModel(
        id: 44,
        fullName: 'Owner',
        phone: '07710000044',
        role: 'owner',
        block: 'A1',
        buildingNumber: '12',
        apartment: '3',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: null,
        isSuperAdmin: false,
      ),
      token: 'owner-token',
    );
  }
}

class _RealtimeOwnerApi extends OwnerApi {
  _RealtimeOwnerApi() : super(Dio());

  int currentOrdersCalls = 0;

  @override
  Future<List<dynamic>> listCurrentOrders() async {
    currentOrdersCalls += 1;
    return <dynamic>[
      <String, dynamic>{
        'id': 12,
        'status': 'pending',
        'total_amount': 1250,
      },
    ];
  }

  @override
  Future<List<dynamic>> listOrderHistory({String? date}) async =>
      const <dynamic>[];

  @override
  Future<Map<String, dynamic>> analytics() async => const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> settlementSummary() async =>
      const <String, dynamic>{};
}

class _FakeRealtimeService extends MaslakiRealtimeService {
  _FakeRealtimeService(this.controller) : super(Dio());

  final StreamController<MaslakiRealtimeEvent> controller;
  String? lastNamespace;

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(
    String namespace,
  ) async {
    lastNamespace = namespace;
    return controller.stream;
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition not met before timeout');
}

void main() {
  test(
    'patchMerchantCourierV2 rejects courierUserId=0 without hitting the API',
    () async {
      final spy = _SpyOwnerApi();
      final container = ProviderContainer(
        overrides: [ownerApiProvider.overrideWithValue(spy)],
      );
      addTearDown(container.dispose);

      final controller = container.read(ownerControllerProvider.notifier);
      final ok = await controller.patchMerchantCourierV2(
        courierUserId: 0,
        isActive: true,
      );

      expect(ok, isFalse);
      expect(spy.patchCalls, 0);
      // A user-facing validation message is surfaced (not a raw backend error).
      expect(container.read(ownerControllerProvider).error, isNotNull);
      expect(container.read(ownerControllerProvider).error, isNotEmpty);
    },
  );

  test('negative courier ids are also rejected client-side', () async {
    final spy = _SpyOwnerApi();
    final container = ProviderContainer(
      overrides: [ownerApiProvider.overrideWithValue(spy)],
    );
    addTearDown(container.dispose);

    final ok = await container
        .read(ownerControllerProvider.notifier)
        .patchMerchantCourierV2(
          courierUserId: -3,
          availabilityStatus: 'available',
        );

    expect(ok, isFalse);
    expect(spy.patchCalls, 0);
  });

  test(
    'setMerchantOpenStatus sends only the store availability field',
    () async {
      final spy = _SpyOwnerApi();
      final container = ProviderContainer(
        overrides: [ownerApiProvider.overrideWithValue(spy)],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(ownerControllerProvider.notifier)
          .setMerchantOpenStatus(isOpen: false);

      expect(ok, isTrue);
      expect(spy.merchantUpdateCalls, 1);
      expect(spy.lastMerchantUpdateBody, {'isOpen': false});
      expect(container.read(ownerControllerProvider).merchant?.isOpen, isFalse);
    },
  );

  test('owner order realtime notification refreshes current orders', () async {
    final api = _RealtimeOwnerApi();
    final realtimeController = StreamController<MaslakiRealtimeEvent>.broadcast();
    final realtime = _FakeRealtimeService(realtimeController);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
        ownerApiProvider.overrideWithValue(api),
        maslakiRealtimeServiceProvider.overrideWithValue(realtime),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await realtimeController.close();
    });

    container.read(ownerControllerProvider.notifier).startLiveOrders();
    await _waitUntil(() => realtime.lastNamespace == 'notifications');
    final callsBeforeEvent = api.currentOrdersCalls;

    realtimeController.add(
      const MaslakiRealtimeEvent(
        topic: 'notifications:user:44',
        event: 'notification',
        data: <String, dynamic>{
          'notification': <String, dynamic>{
            'id': 99,
            'type': 'owner_new_order',
            'orderId': 12,
            'payload': <String, dynamic>{
              'orderId': 12,
              'target': 'merchant_order_details',
            },
          },
        },
        eventId: 7,
        envelope: <String, dynamic>{},
      ),
    );

    await _waitUntil(() => api.currentOrdersCalls > callsBeforeEvent);
  });
}
