import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/tracking/tracking_map_utils.dart';

void main() {
  test('order stream location merges immediately into the active snapshot', () {
    final merged = mergeOrderTrackingEvent(
      {
        'order': {'id': 7, 'status': 'on_the_way'},
        'latestLocation': {'latitude': 33.1, 'longitude': 44.1},
      },
      {
        'orderId': 7,
        'status': 'arrived',
        'latestLocation': {'latitude': 33.2, 'longitude': 44.2},
      },
    );

    expect(latLngFromMap(merged['latestLocation'])?.latitude, 33.2);
    expect((merged['order'] as Map)['status'], 'arrived');
    expect(orderTrackingIsActive(merged), isTrue);
  });

  test(
    'taxi stream location merges immediately and terminal status stops live mode',
    () {
      final moved = mergeTaxiTrackingEvent(
        {
          'ride': {'id': 9, 'status': 'ride_started'},
        },
        {
          'rideId': 9,
          'status': 'ride_started',
          'location': {'latitude': 33.3, 'longitude': 44.3},
        },
      );
      expect(latLngFromMap(moved['latestLocation'])?.longitude, 44.3);
      expect(taxiTrackingIsActive(moved), isTrue);

      final completed = mergeTaxiTrackingEvent(moved, {
        'rideId': 9,
        'status': 'completed',
      });
      expect(taxiTrackingIsActive(completed), isFalse);
    },
  );

  test(
    'courier publishing requires foreground permission assignment and active order',
    () {
      expect(
        canPublishCourierLocation(
          lifecycleResumed: true,
          permissionGranted: true,
          assigned: true,
          status: 'on_the_way',
        ),
        isTrue,
      );
      expect(
        canPublishCourierLocation(
          lifecycleResumed: false,
          permissionGranted: true,
          assigned: true,
          status: 'on_the_way',
        ),
        isFalse,
      );
      expect(
        canPublishCourierLocation(
          lifecycleResumed: true,
          permissionGranted: false,
          assigned: true,
          status: 'arrived',
        ),
        isFalse,
      );
      expect(
        canPublishCourierLocation(
          lifecycleResumed: true,
          permissionGranted: true,
          assigned: true,
          status: 'delivered',
        ),
        isFalse,
      );
    },
  );

  test('taxi ride publishing rejects background and terminal contexts', () {
    expect(
      canPublishTaxiRideLocation(
        lifecycleResumed: true,
        permissionGranted: true,
        assigned: true,
        status: 'captain_arriving',
      ),
      isTrue,
    );
    expect(
      canPublishTaxiRideLocation(
        lifecycleResumed: false,
        permissionGranted: true,
        assigned: true,
        status: 'ride_started',
      ),
      isFalse,
    );
    expect(
      canPublishTaxiRideLocation(
        lifecycleResumed: true,
        permissionGranted: true,
        assigned: true,
        status: 'completed',
      ),
      isFalse,
    );
  });
}
