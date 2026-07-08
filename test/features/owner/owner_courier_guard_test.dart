import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/data/owner_api.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';

/// Records courier PATCH calls so we can assert the app never sends an invalid
/// courier id (e.g. 0 from a row with a missing user_id) to
/// PATCH /api/merchant/couriers/:id.
class _SpyOwnerApi extends OwnerApi {
  _SpyOwnerApi() : super(Dio());

  int patchCalls = 0;
  int? lastCourierUserId;

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

void main() {
  test('patchMerchantCourierV2 rejects courierUserId=0 without hitting the API', () async {
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
  });

  test('negative courier ids are also rejected client-side', () async {
    final spy = _SpyOwnerApi();
    final container = ProviderContainer(
      overrides: [ownerApiProvider.overrideWithValue(spy)],
    );
    addTearDown(container.dispose);

    final ok = await container
        .read(ownerControllerProvider.notifier)
        .patchMerchantCourierV2(courierUserId: -3, availabilityStatus: 'available');

    expect(ok, isFalse);
    expect(spy.patchCalls, 0);
  });
}
