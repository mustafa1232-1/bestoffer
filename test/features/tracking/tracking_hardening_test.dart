import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';
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
    'taxi route starts at captain before pickup and switches to live location after pickup',
    () {
      final beforePickup = <String, dynamic>{
        'id': 9,
        'status': 'captain_assigned',
        'captainLatitude': 33.3152,
        'captainLongitude': 44.3648,
        'pickup': {'latitude': 33.3128, 'longitude': 44.3615},
        'dropoff': {'latitude': 33.3201, 'longitude': 44.3750},
      };

      expect(taxiRideHasPickedUp(beforePickup), isFalse);
      expect(taxiRideRouteStartPoint(beforePickup)?.latitude, 33.3152);
      expect(taxiRideRouteEndPoint(beforePickup)?.latitude, 33.3128);

      final afterPickup = <String, dynamic>{
        'id': 9,
        'status': 'ride_started',
        'latestLocation': {
          'latitude': 33.3181,
          'longitude': 44.3701,
          'updatedAt': '2026-07-13T10:00:00Z',
        },
        'pickup': {'latitude': 33.3128, 'longitude': 44.3615},
        'dropoff': {'latitude': 33.3201, 'longitude': 44.3750},
      };

      expect(taxiRideHasPickedUp(afterPickup), isTrue);
      expect(taxiRideRouteStartPoint(afterPickup)?.latitude, 33.3181);
      expect(taxiRideRouteEndPoint(afterPickup)?.latitude, 33.3201);
    },
  );

  test('searching taxi rides stay out of active-tracking mode', () {
    final searching = {
      'ride': {'id': 22, 'status': 'searching', 'currentBidId': 11},
    };

    expect(
      taxiRideDisplayState(searching['ride'] as Map<String, dynamic>),
      'negotiating',
    );
    expect(taxiTrackingIsActive(searching), isFalse);
  });

  test('assigned taxi rides normalize to active display state', () {
    final ride = taxiRideViewFromEnvelope({
      'ride': {
        'id': 77,
        'status': 'captain_assigned',
        'pickup': {'latitude': 33.3128, 'longitude': 44.3615},
        'dropoff': {'latitude': 33.3201, 'longitude': 44.3750},
        'captain': {
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
          'latitude': 33.3152,
          'longitude': 44.3648,
        },
      },
    });

    expect(ride, isNotNull);
    expect(taxiRideDisplayState(ride), 'active');
    expect(taxiTrackingIsActive({'ride': ride}), isTrue);
  });

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
