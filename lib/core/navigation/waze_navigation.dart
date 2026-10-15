import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Waze navigation when coordinates are available, with web and Google
/// Maps fallbacks for devices without the Waze app.
Future<bool> openWazeNavigation({
  required double? latitude,
  required double? longitude,
  String? query,
}) async {
  final lat = latitude;
  final lng = longitude;
  final destination = lat != null && lng != null ? LatLng(lat, lng) : null;

  if (destination != null) {
    final appUri = Uri.parse(
      'waze://?ll=${destination.latitude},${destination.longitude}&navigate=yes',
    );
    if (await _launch(appUri)) return true;

    final webUri = Uri.parse(
      'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes&utm_source=maslaki',
    );
    if (await _launch(webUri)) return true;

    final mapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${destination.latitude},${destination.longitude}',
    );
    if (await _launch(mapsUri)) return true;
  }

  final text = (query ?? '').trim();
  if (text.isNotEmpty) {
    final wazeSearchUri = Uri.https('waze.com', '/ul', {
      'q': text,
      'utm_source': 'maslaki',
    });
    if (await _launch(wazeSearchUri)) return true;

    return _launch(
      Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(text)}',
      ),
    );
  }
  return false;
}

Future<bool> _launch(Uri uri) async {
  try {
    if (!await canLaunchUrl(uri)) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
