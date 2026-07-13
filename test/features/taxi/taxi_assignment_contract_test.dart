import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';

void main() {
  test('taxi assignment contract merges legacy ride and canonical assignment', () {
    final envelope = <String, dynamic>{
      'ride': <String, dynamic>{
        'id': 41,
        'status': 'captain_assigned',
        'currentBidId': 11,
        'pickup': <String, dynamic>{
          'latitude': 33.31456,
          'longitude': 44.36611,
          'label': 'Bismayah Gate',
        },
        'dropoff': <String, dynamic>{
          'latitude': 33.32091,
          'longitude': 44.39118,
          'label': 'Central Mall',
        },
        'proposedFareIqd': 14500,
        'agreedFareIqd': 16000,
        'captain': <String, dynamic>{
          'fullName': 'Captain Noor',
          'phone': '07711111111',
          'carMake': 'Toyota',
          'carModel': 'Corolla',
          'carYear': 2022,
          'carColor': 'Silver',
          'plateNumber': 'TX-001',
        },
      },
      'assignment': <String, dynamic>{
        'rideId': 41,
        'status': 'captain_assigned',
        'customerFare': 14500,
        'finalFare': 16000,
        'currency': 'IQD',
        'pickupAddress': 'Bismayah Gate',
        'pickupLatitude': 33.31456,
        'pickupLongitude': 44.36611,
        'destinationAddress': 'Central Mall',
        'destinationLatitude': 33.32091,
        'destinationLongitude': 44.39118,
        'captain': <String, dynamic>{
          'captainId': 77,
          'captainName': 'Captain Noor',
          'captainPhone': '07711111111',
          'captainRating': 4.9,
          'captainRatingCount': 128,
          'captainCompletedTrips': 128,
        },
        'vehicle': <String, dynamic>{
          'vehicleId': 5,
          'vehicleMake': 'Toyota',
          'vehicleModel': 'Corolla',
          'vehicleYear': 2022,
          'vehicleColor': 'Silver',
          'vehicleType': 'sedan',
          'vehiclePlate': 'TX-001',
          'vehicleNumber': 'TX-001',
        },
      },
    };

    final assignment = taxiAssignmentFromEnvelope(envelope);
    final ride = taxiRideViewFromEnvelope(envelope);

    expect(assignment, isNotNull);
    expect(ride, isNotNull);
    expect(assignment!['rideId'], 41);
    expect(assignment['finalFare'], 16000);
    expect(assignment['captain']['captainName'], 'Captain Noor');
    expect(assignment['vehicle']['vehiclePlate'], 'TX-001');

    expect(ride!['id'], 41);
    expect(ride['finalFare'], 16000);
    expect(ride['currentBidId'], 11);
    expect(ride['captain']['fullName'], 'Captain Noor');
    expect(ride['vehicle']['vehicleMake'], 'Toyota');
    expect(ride['assignment']['rideId'], 41);
  });
}
