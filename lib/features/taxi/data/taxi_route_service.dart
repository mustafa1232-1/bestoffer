import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class TaxiRouteService {
  TaxiRouteService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {
                'User-Agent': 'BestOfferTaxi/1.0 (support@bestoffer.app)',
              },
            ),
          );

  final Dio _dio;
  static const Distance _distance = Distance();

  double distanceMeters(LatLng from, LatLng to) {
    return _distance.as(LengthUnit.Meter, from, to);
  }

  Future<List<LatLng>> fetchDrivingRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final response = await _dio.get(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': false,
        'alternatives': false,
      },
    );

    final data = response.data;
    if (data is! Map) {
      return [from, to];
    }

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      return [from, to];
    }

    final first = routes.first;
    if (first is! Map) {
      return [from, to];
    }

    final geometry = first['geometry'];
    if (geometry is! Map) {
      return [from, to];
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List) {
      return [from, to];
    }

    final points = <LatLng>[];
    for (final item in coordinates) {
      if (item is! List || item.length < 2) continue;
      final lng = _toDouble(item[0]);
      final lat = _toDouble(item[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    if (points.length < 2) {
      return [from, to];
    }
    return points;
  }

  Future<void> openWazeNavigation(LatLng destination) async {
    final waze = Uri.parse(
      'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes',
    );
    if (await launchUrl(waze, mode: LaunchMode.externalApplication)) {
      return;
    }

    final googleFallback = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${destination.latitude},${destination.longitude}',
    );
    final opened = await launchUrl(
      googleFallback,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw Exception('NO_MAP_APP');
    }
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
