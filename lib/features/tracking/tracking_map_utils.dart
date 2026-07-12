import 'package:latlong2/latlong.dart';

const basmayaTrackingCenter = LatLng(33.2388, 44.4975);

Map<String, dynamic>? trackingMap(dynamic raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

String? trackingString(dynamic value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

String? trackingNestedString(dynamic raw, List<String> path) {
  dynamic current = raw;
  for (final segment in path) {
    final map = trackingMap(current);
    if (map == null) return null;
    current = map[segment];
  }
  return trackingString(current);
}

LatLng approximateBasmayaAddressPoint({
  required String block,
  required String buildingNumber,
}) {
  var lat = basmayaTrackingCenter.latitude;
  var lng = basmayaTrackingCenter.longitude;

  try {
    final normalizedBlock = block.trim().toUpperCase();
    final letter = normalizedBlock.isNotEmpty ? normalizedBlock[0] : 'A';
    final sector = normalizedBlock.length > 1
        ? int.tryParse(normalizedBlock.substring(1)) ?? 1
        : 1;

    if (letter == 'A') {
      lat += (sector - 5) * 0.003;
      lng += -0.005;
    } else if (letter == 'B') {
      lat += (sector - 4) * 0.003;
      lng += 0.005;
    }

    final buildNum =
        int.tryParse(buildingNumber.replaceAll(RegExp(r'[^\d]'), '')) ?? 1;
    lng += (buildNum - 11) * 0.001;
  } catch (_) {
    // Keep the fallback center when address parsing is incomplete.
  }

  return LatLng(lat, lng);
}

LatLng? latLngFromMap(dynamic raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final latitude = double.tryParse('${map['latitude'] ?? map['lat'] ?? ''}');
  final longitude = double.tryParse(
    '${map['longitude'] ?? map['lng'] ?? map['lon'] ?? ''}',
  );
  if (latitude == null || longitude == null) return null;
  return LatLng(latitude, longitude);
}

const _terminalOrderStatuses = <String>{
  'delivered',
  'received',
  'completed',
  'cancelled',
  'failed',
  'failed_delivery',
  'returned',
  'returned_if_needed',
};

const _terminalTaxiStatuses = <String>{'completed', 'cancelled', 'expired'};
const _activeTaxiStatuses = <String>{
  'captain_assigned',
  'captain_arriving',
  'ride_started',
};

String? _trackingStatus(Map<String, dynamic>? envelope) {
  final nested =
      trackingMap(envelope?['order'] ?? envelope?['ride'] ?? envelope?['assignment']);
  return trackingString(
    nested?['status'] ?? envelope?['status'],
  )?.toLowerCase();
}

String? taxiRideDisplayState(Map<String, dynamic>? ride) {
  final status = trackingString(ride?['status'])?.toLowerCase();
  if (status == null) return null;
  if (_terminalTaxiStatuses.contains(status)) return 'terminal';
  if (_activeTaxiStatuses.contains(status)) return 'active';
  if (status == 'searching') {
    return ride?['currentBidId'] != null ? 'negotiating' : 'searching';
  }
  return status;
}

bool orderTrackingIsActive(Map<String, dynamic>? snapshot) {
  final status = _trackingStatus(snapshot);
  return status == null || !_terminalOrderStatuses.contains(status);
}

bool taxiTrackingIsActive(Map<String, dynamic>? envelope) {
  final status = _trackingStatus(envelope);
  return status != null && _activeTaxiStatuses.contains(status);
}

Map<String, dynamic> mergeOrderTrackingEvent(
  Map<String, dynamic>? current,
  Map<String, dynamic> event,
) {
  final merged = <String, dynamic>{...?current};
  final eventOrder = trackingMap(event['order']);
  final currentOrder = trackingMap(merged['order']);
  if (eventOrder != null) {
    merged['order'] = <String, dynamic>{...?currentOrder, ...eventOrder};
  } else if (event['status'] != null && currentOrder != null) {
    merged['order'] = <String, dynamic>{
      ...currentOrder,
      'status': event['status'],
    };
  }
  for (final key in const [
    'stage',
    'latestLocation',
    'lastUpdatedAt',
    'destination',
    'courier',
  ]) {
    if (event[key] != null) merged[key] = event[key];
  }
  return merged;
}

Map<String, dynamic> mergeTaxiTrackingEvent(
  Map<String, dynamic>? current,
  Map<String, dynamic> event,
) {
  final merged = <String, dynamic>{...?current};
  final eventRide = trackingMap(event['ride']);
  final currentRide = trackingMap(merged['ride']);
  if (eventRide != null) {
    merged['ride'] = <String, dynamic>{...?currentRide, ...eventRide};
  } else if (event['status'] != null && currentRide != null) {
    merged['ride'] = <String, dynamic>{
      ...currentRide,
      'status': event['status'],
    };
  }
  final eventAssignment = trackingMap(event['assignment']);
  final currentAssignment = trackingMap(merged['assignment']);
  if (eventAssignment != null) {
    merged['assignment'] = <String, dynamic>{
      ...?currentAssignment,
      ...eventAssignment,
    };
  } else if (event['assignmentStatus'] != null && currentAssignment != null) {
    merged['assignment'] = <String, dynamic>{
      ...currentAssignment,
      'status': event['assignmentStatus'],
    };
  }
  final location = event['location'] ?? event['latestLocation'];
  if (location != null) merged['latestLocation'] = location;
  return merged;
}

bool canPublishCourierLocation({
  required bool lifecycleResumed,
  required bool permissionGranted,
  required bool assigned,
  required String status,
}) {
  return lifecycleResumed &&
      permissionGranted &&
      assigned &&
      const {
        'ready_for_delivery',
        'on_the_way',
        'arrived',
      }.contains(status.trim().toLowerCase());
}

bool canPublishTaxiRideLocation({
  required bool lifecycleResumed,
  required bool permissionGranted,
  required bool assigned,
  required String status,
}) {
  return lifecycleResumed &&
      permissionGranted &&
      assigned &&
      const {
        'captain_assigned',
        'captain_arriving',
        'ride_started',
      }.contains(status.trim().toLowerCase());
}
