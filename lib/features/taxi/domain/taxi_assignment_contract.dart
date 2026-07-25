import 'dart:math' as math;

Map<String, dynamic>? _map(dynamic raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

String? _string(dynamic value) {
  final text = value == null ? '' : value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

double? _double(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _int(dynamic value) {
  final parsed = _double(value);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed.round();
}

Map<String, dynamic>? _pickupLike({
  required Map<String, dynamic>? ride,
  required Map<String, dynamic>? assignment,
}) {
  final raw = _map(ride?['pickup']) ?? _map(assignment?['pickup']);
  final latitude = _double(raw?['latitude'] ?? assignment?['pickupLatitude']);
  final longitude = _double(
    raw?['longitude'] ?? assignment?['pickupLongitude'],
  );
  final label = _string(
    raw?['label'] ??
        raw?['addressText'] ??
        assignment?['pickupAddress'] ??
        ride?['pickupAddress'],
  );
  if (latitude == null && longitude == null && label == null) return null;
  final result = <String, dynamic>{};
  if (latitude != null) result['latitude'] = latitude;
  if (longitude != null) result['longitude'] = longitude;
  if (label != null) result['label'] = label;
  return result;
}

Map<String, dynamic>? _dropoffLike({
  required Map<String, dynamic>? ride,
  required Map<String, dynamic>? assignment,
}) {
  final raw = _map(ride?['dropoff']) ?? _map(assignment?['dropoff']);
  final latitude = _double(
    raw?['latitude'] ?? assignment?['destinationLatitude'],
  );
  final longitude = _double(
    raw?['longitude'] ?? assignment?['destinationLongitude'],
  );
  final label = _string(
    raw?['label'] ??
        raw?['addressText'] ??
        assignment?['destinationAddress'] ??
        ride?['destinationAddress'],
  );
  if (latitude == null && longitude == null && label == null) return null;
  final result = <String, dynamic>{};
  if (latitude != null) result['latitude'] = latitude;
  if (longitude != null) result['longitude'] = longitude;
  if (label != null) result['label'] = label;
  return result;
}

double? _distanceMeters({
  required Map<String, dynamic>? pickup,
  required Map<String, dynamic>? dropoff,
}) {
  final lat1 = _double(pickup?['latitude']);
  final lng1 = _double(pickup?['longitude']);
  final lat2 = _double(dropoff?['latitude']);
  final lng2 = _double(dropoff?['longitude']);
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
    return null;
  }

  const earthRadius = 6371000.0;
  final aLat = lat1 * math.pi / 180;
  final aLng = lng1 * math.pi / 180;
  final bLat = lat2 * math.pi / 180;
  final bLng = lng2 * math.pi / 180;
  final deltaLat = bLat - aLat;
  final deltaLng = bLng - aLng;
  final sinLat = math.sin(deltaLat / 2);
  final sinLng = math.sin(deltaLng / 2);
  final a = sinLat * sinLat + math.cos(aLat) * math.cos(bLat) * sinLng * sinLng;
  return (2 * earthRadius * math.asin(math.min(1, math.sqrt(a))));
}

Map<String, dynamic>? _assignmentFromRide(
  Map<String, dynamic>? ride, {
  Map<String, dynamic>? latestLocation,
}) {
  if (ride == null) return null;

  final pickup = _pickupLike(ride: ride, assignment: null);
  final dropoff = _dropoffLike(ride: ride, assignment: null);
  final captain = _map(ride['captain']);
  final vehicle =
      _map(ride['vehicle']) ??
      (captain == null
          ? null
          : {
              if (_string(captain['vehicleId']) != null)
                'vehicleId': _int(captain['vehicleId']),
              'vehicleMake': _string(captain['carMake']),
              'vehicleModel': _string(captain['carModel']),
              'vehicleYear': _int(captain['carYear']),
              'vehicleColor': _string(captain['carColor']),
              'vehicleType': _string(captain['vehicleType']),
              'vehiclePlate': _string(captain['plateNumber']),
              'vehicleNumber': _string(captain['plateNumber']),
              'vehiclePlateGovernorate': _string(captain['plateGovernorate']),
              'vehiclePlateCategory': _string(captain['plateCategory']),
              'vehiclePlateLetter': _string(captain['plateLetter']),
              'vehiclePlateDigits': _string(captain['plateDigits']),
              'vehicleImage': _string(captain['carImageUrl']),
            });

  final captainLatitude = _double(
    latestLocation?['latitude'] ?? latestLocation?['lat'],
  );
  final captainLongitude = _double(
    latestLocation?['longitude'] ?? latestLocation?['lng'],
  );
  final captainDistanceMeters =
      pickup != null && captainLatitude != null && captainLongitude != null
      ? _distanceMeters(
          pickup: pickup,
          dropoff: {'latitude': captainLatitude, 'longitude': captainLongitude},
        )
      : null;

  final routeDistance =
      _double(ride['routeDistanceMeters']) ??
      _double(ride['routeDistance']) ??
      _distanceMeters(pickup: pickup, dropoff: dropoff);
  final routeDuration =
      _int(ride['routeDurationSeconds']) ??
      _int(ride['routeDuration']) ??
      (routeDistance == null
          ? null
          : ((routeDistance / 1000 / 35) * 3600).round());
  final estimatedArrivalMinutes =
      _int(ride['estimatedArrivalMinutes']) ??
      (captainDistanceMeters == null
          ? null
          : math.max(1, ((captainDistanceMeters / 1000 / 30) * 60).ceil()));

  final customerFare = _int(ride['customerFare'] ?? ride['proposedFareIqd']);
  final finalFare = _int(
    ride['finalFare'] ?? ride['agreedFareIqd'] ?? ride['proposedFareIqd'],
  );

  final captainSnapshot = captain == null
      ? null
      : (() {
          final snapshot = <String, dynamic>{
            'captainId': _int(
              captain['captainId'] ?? captain['id'] ?? ride['captainId'],
            ),
            'captainName': _string(
              captain['captainName'] ?? captain['fullName'] ?? captain['name'],
            ),
            'captainPhoto': _string(
              captain['captainPhoto'] ??
                  captain['profileImageUrl'] ??
                  captain['imageUrl'],
            ),
            'captainRating': _double(
              captain['captainRating'] ?? captain['ratingAvg'],
            ),
            'captainRatingCount': _int(
              captain['captainRatingCount'] ?? captain['ratingCount'],
            ),
            'captainCompletedTrips': _int(
              captain['captainCompletedTrips'] ?? captain['ridesCount'],
            ),
            'captainPhone': _string(
              captain['captainPhone'] ?? captain['phone'],
            ),
            'captainLatitude': captainLatitude,
            'captainLongitude': captainLongitude,
            'captainHeading': _double(
              latestLocation?['headingDeg'] ?? latestLocation?['heading_deg'],
            ),
            'captainDistanceMeters': captainDistanceMeters,
            'captainEstimatedArrivalMinutes': estimatedArrivalMinutes,
          };
          snapshot.removeWhere((key, value) => value == null);
          return snapshot;
        })();

  final vehicleSnapshot = vehicle == null
      ? null
      : (() {
          final snapshot = <String, dynamic>{
            'vehicleId': _int(vehicle['vehicleId'] ?? vehicle['id']),
            'vehicleMake': _string(
              vehicle['vehicleMake'] ?? vehicle['make'] ?? vehicle['carMake'],
            ),
            'vehicleModel': _string(
              vehicle['vehicleModel'] ??
                  vehicle['model'] ??
                  vehicle['carModel'],
            ),
            'vehicleYear': _int(
              vehicle['vehicleYear'] ?? vehicle['year'] ?? vehicle['carYear'],
            ),
            'vehicleColor': _string(
              vehicle['vehicleColor'] ??
                  vehicle['color'] ??
                  vehicle['carColor'],
            ),
            'vehicleType': _string(vehicle['vehicleType'] ?? vehicle['type']),
            'vehiclePlate': _string(
              vehicle['vehiclePlate'] ?? vehicle['plate'],
            ),
            'vehiclePlateGovernorate': _string(
              vehicle['vehiclePlateGovernorate'] ?? vehicle['plateGovernorate'],
            ),
            'vehiclePlateCategory': _string(
              vehicle['vehiclePlateCategory'] ?? vehicle['plateCategory'],
            ),
            'vehiclePlateLetter': _string(
              vehicle['vehiclePlateLetter'] ?? vehicle['plateLetter'],
            ),
            'vehiclePlateDigits': _string(
              vehicle['vehiclePlateDigits'] ?? vehicle['plateDigits'],
            ),
            'vehicleNumber': _string(
              vehicle['vehicleNumber'] ?? vehicle['number'],
            ),
            'vehicleImage': _string(
              vehicle['vehicleImage'] ??
                  vehicle['imageUrl'] ??
                  vehicle['carImageUrl'],
            ),
          };
          snapshot.removeWhere((key, value) => value == null);
          return snapshot;
        })();

  return {
    'rideId': _int(ride['rideId'] ?? ride['id']),
    'status': _string(ride['status']),
    'customerFare': customerFare,
    'finalFare': finalFare,
    'currency': _string(ride['currency']) ?? 'IQD',
    'pickupAddress': _string(ride['pickupAddress'] ?? pickup?['label']),
    'pickupLatitude': _double(ride['pickupLatitude'] ?? pickup?['latitude']),
    'pickupLongitude': _double(ride['pickupLongitude'] ?? pickup?['longitude']),
    'destinationAddress': _string(
      ride['destinationAddress'] ?? dropoff?['label'],
    ),
    'destinationLatitude': _double(
      ride['destinationLatitude'] ?? dropoff?['latitude'],
    ),
    'destinationLongitude': _double(
      ride['destinationLongitude'] ?? dropoff?['longitude'],
    ),
    'routeDistance': routeDistance,
    'routeDuration': routeDuration,
    'estimatedArrivalMinutes': estimatedArrivalMinutes,
    'assignedAt': ride['assignedAt'] ?? ride['acceptedAt'],
    'updatedAt': ride['updatedAt'],
    'captain': captainSnapshot,
    'vehicle': vehicleSnapshot,
  }..removeWhere((key, value) => value == null);
}

Map<String, dynamic>? taxiAssignmentFromEnvelope(dynamic raw) {
  final envelope = _map(raw);
  if (envelope == null) return null;
  final assignment = _map(envelope['assignment']);
  if (assignment != null) return assignment;
  final ride = _map(envelope['ride'] ?? raw);
  return _assignmentFromRide(
    ride,
    latestLocation: _map(envelope['latestLocation']),
  );
}

Map<String, dynamic>? taxiRideViewFromEnvelope(dynamic raw) {
  final envelope = _map(raw);
  if (envelope == null) return null;
  final ride = _map(envelope['ride'] ?? raw);
  final assignment =
      taxiAssignmentFromEnvelope(envelope) ??
      _assignmentFromRide(
        ride,
        latestLocation: _map(envelope['latestLocation']),
      );
  if (ride == null && assignment == null) return null;

  final output = <String, dynamic>{...?ride};
  final latestLocation = _map(envelope['latestLocation']);
  final pick = _pickupLike(ride: ride, assignment: assignment);
  final drop = _dropoffLike(ride: ride, assignment: assignment);

  if (assignment != null) {
    output['assignment'] = assignment;
    output['id'] = assignment['rideId'] ?? output['id'];
    output['rideId'] = assignment['rideId'];
    output['status'] = assignment['status'] ?? output['status'];
    output['customerFare'] = assignment['customerFare'];
    output['finalFare'] = assignment['finalFare'];
    output['currency'] = assignment['currency'];
    output['pickupAddress'] = assignment['pickupAddress'];
    output['pickupLatitude'] = assignment['pickupLatitude'];
    output['pickupLongitude'] = assignment['pickupLongitude'];
    output['destinationAddress'] = assignment['destinationAddress'];
    output['destinationLatitude'] = assignment['destinationLatitude'];
    output['destinationLongitude'] = assignment['destinationLongitude'];
    output['routeDistance'] = assignment['routeDistance'];
    output['routeDistanceMeters'] = assignment['routeDistance'];
    output['routeDuration'] = assignment['routeDuration'];
    output['routeDurationSeconds'] = assignment['routeDuration'];
    output['estimatedArrivalMinutes'] = assignment['estimatedArrivalMinutes'];
    output['assignedAt'] = assignment['assignedAt'];
    output['acceptedAt'] = assignment['assignedAt'];
    output['updatedAt'] = assignment['updatedAt'];
    output['agreedFareIqd'] =
        assignment['finalFare'] ?? output['agreedFareIqd'];
    output['proposedFareIqd'] =
        assignment['customerFare'] ?? output['proposedFareIqd'];
  }
  if (latestLocation != null) {
    output['latestLocation'] = latestLocation;
  }

  if (pick != null) output['pickup'] = pick;
  if (drop != null) output['dropoff'] = drop;

  final captainFromRide = _map(output['captain']);
  final captainFromAssignment = _map(assignment?['captain']);
  final vehicleFromAssignment = _map(assignment?['vehicle']);
  final mergedCaptain = <String, dynamic>{
    ...?captainFromRide,
    ...?captainFromAssignment,
  };
  if (vehicleFromAssignment != null) {
    mergedCaptain['vehicle'] = vehicleFromAssignment;
    mergedCaptain['vehicleType'] ??= vehicleFromAssignment['vehicleType'];
    mergedCaptain['carMake'] ??=
        vehicleFromAssignment['vehicleMake'] ?? vehicleFromAssignment['make'];
    mergedCaptain['carModel'] ??=
        vehicleFromAssignment['vehicleModel'] ?? vehicleFromAssignment['model'];
    mergedCaptain['carYear'] ??=
        vehicleFromAssignment['vehicleYear'] ?? vehicleFromAssignment['year'];
    mergedCaptain['carColor'] ??=
        vehicleFromAssignment['vehicleColor'] ?? vehicleFromAssignment['color'];
    mergedCaptain['plateNumber'] ??=
        vehicleFromAssignment['vehiclePlate'] ?? vehicleFromAssignment['plate'];
    mergedCaptain['plateGovernorate'] ??=
        vehicleFromAssignment['vehiclePlateGovernorate'];
    mergedCaptain['plateCategory'] ??=
        vehicleFromAssignment['vehiclePlateCategory'];
    mergedCaptain['plateLetter'] ??=
        vehicleFromAssignment['vehiclePlateLetter'];
    mergedCaptain['plateDigits'] ??=
        vehicleFromAssignment['vehiclePlateDigits'];
    mergedCaptain['carImageUrl'] ??=
        vehicleFromAssignment['vehicleImage'] ??
        vehicleFromAssignment['imageUrl'];
  }
  if (mergedCaptain.isNotEmpty) {
    output['captain'] = mergedCaptain;
  }

  if (vehicleFromAssignment != null) {
    output['vehicle'] = vehicleFromAssignment;
  }
  final mergedVehicle = _map(output['vehicle']);
  final assignmentCaptain = _map(assignment?['captain']);

  final captainName =
      _string(assignmentCaptain?['captainName']) ??
      _string(captainFromRide?['fullName']) ??
      _string(captainFromRide?['name']);
  final captainPhotoUrl =
      _string(assignmentCaptain?['captainPhoto']) ??
      _string(captainFromRide?['profileImageUrl']) ??
      _string(captainFromRide?['imageUrl']) ??
      _string(captainFromRide?['photoUrl']);

  output['rideStatus'] = _string(output['status']);
  output['proposedFare'] = output['customerFare'];
  output['distanceMeters'] =
      assignment?['routeDistance'] ?? output['routeDistance'];
  output['durationSeconds'] =
      assignment?['routeDuration'] ?? output['routeDuration'];
  output['captainName'] = captainName;
  output['captainPhotoUrl'] = captainPhotoUrl;
  output['captainPhoto'] = captainPhotoUrl;
  output['captainPhone'] =
      _string(assignmentCaptain?['captainPhone']) ??
      _string(captainFromRide?['phone']);
  output['captainRating'] =
      assignmentCaptain?['captainRating'] ?? captainFromRide?['ratingAvg'];
  output['captainRatingCount'] =
      assignmentCaptain?['captainRatingCount'] ??
      captainFromRide?['ratingCount'] ??
      captainFromRide?['ridesCount'];
  output['captainCompletedTrips'] =
      assignmentCaptain?['captainCompletedTrips'] ??
      captainFromRide?['ridesCount'];
  output['captainLatitude'] =
      assignmentCaptain?['captainLatitude'] ??
      captainFromRide?['latitude'] ??
      output['captainLatitude'];
  output['captainLongitude'] =
      assignmentCaptain?['captainLongitude'] ??
      captainFromRide?['longitude'] ??
      output['captainLongitude'];
  output['captainHeading'] = assignmentCaptain?['captainHeading'];
  output['captainDistanceMeters'] = assignmentCaptain?['captainDistanceMeters'];
  output['captainEstimatedArrivalMinutes'] =
      assignmentCaptain?['captainEstimatedArrivalMinutes'] ??
      output['estimatedArrivalMinutes'];
  output['vehicleId'] = mergedVehicle?['vehicleId'];
  output['vehicleMake'] = mergedVehicle?['vehicleMake'];
  output['vehicleModel'] = mergedVehicle?['vehicleModel'];
  output['vehicleYear'] = mergedVehicle?['vehicleYear'];
  output['vehicleColor'] = mergedVehicle?['vehicleColor'];
  output['vehicleType'] = mergedVehicle?['vehicleType'];
  output['vehiclePlate'] = mergedVehicle?['vehiclePlate'];
  output['vehiclePlateGovernorate'] = mergedVehicle?['vehiclePlateGovernorate'];
  output['vehiclePlateCategory'] = mergedVehicle?['vehiclePlateCategory'];
  output['vehiclePlateLetter'] = mergedVehicle?['vehiclePlateLetter'];
  output['vehiclePlateDigits'] = mergedVehicle?['vehiclePlateDigits'];
  output['vehicleNumber'] = mergedVehicle?['vehicleNumber'];
  output['vehicleImage'] = mergedVehicle?['vehicleImage'];
  output['pickupAddress'] = output['pickupAddress'] ?? pick?['label'];
  output['destinationAddress'] = output['destinationAddress'] ?? drop?['label'];

  return output;
}
