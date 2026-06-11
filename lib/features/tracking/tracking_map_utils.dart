import 'package:latlong2/latlong.dart';

const basmayaTrackingCenter = LatLng(33.2388, 44.4975);

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
  final latitude =
      double.tryParse('${map['latitude'] ?? map['lat'] ?? ''}');
  final longitude =
      double.tryParse('${map['longitude'] ?? map['lng'] ?? map['lon'] ?? ''}');
  if (latitude == null || longitude == null) return null;
  return LatLng(latitude, longitude);
}
