import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class TaxiRoutePreview {
  const TaxiRoutePreview({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int? durationSeconds;
}

class TaxiRouteService {
  TaxiRouteService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'User-Agent': 'MaslakiTaxi/1.0 (support@maslaki.app)'},
            ),
          );

  final Dio _dio;
  static const Distance _distance = Distance();

  double distanceMeters(LatLng from, LatLng to) {
    return _distance.as(LengthUnit.Meter, from, to);
  }

  double polylineDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceMeters(points[i - 1], points[i]);
    }
    return total;
  }

  Future<TaxiRoutePreview> fetchDrivingRoutePreview({
    required LatLng from,
    required LatLng to,
  }) async {
    final fallbackDistance = distanceMeters(from, to);
    final response = await _dio.get(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': false,
        'alternatives': false,
      },
    );

    final data = response.data;
    if (data is! Map) {
      return TaxiRoutePreview(
        points: [from, to],
        distanceMeters: fallbackDistance,
        durationSeconds: null,
      );
    }

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      return TaxiRoutePreview(
        points: [from, to],
        distanceMeters: fallbackDistance,
        durationSeconds: null,
      );
    }

    final first = routes.first;
    if (first is! Map) {
      return TaxiRoutePreview(
        points: [from, to],
        distanceMeters: fallbackDistance,
        durationSeconds: null,
      );
    }

    final geometry = first['geometry'];
    if (geometry is! Map) {
      return TaxiRoutePreview(
        points: [from, to],
        distanceMeters: fallbackDistance,
        durationSeconds: _toInt(first['duration']),
      );
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List) {
      return TaxiRoutePreview(
        points: [from, to],
        distanceMeters: _toDouble(first['distance']) ?? fallbackDistance,
        durationSeconds: _toInt(first['duration']),
      );
    }

    final points = <LatLng>[];
    for (final item in coordinates) {
      if (item is! List || item.length < 2) continue;
      final lng = _toDouble(item[0]);
      final lat = _toDouble(item[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    final resolvedPoints = points.length < 2 ? <LatLng>[from, to] : points;
    return TaxiRoutePreview(
      points: resolvedPoints,
      distanceMeters:
          _toDouble(first['distance']) ?? polylineDistanceMeters(resolvedPoints),
      durationSeconds: _toInt(first['duration']),
    );
  }

  Future<List<LatLng>> fetchDrivingRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final preview = await fetchDrivingRoutePreview(from: from, to: to);
    return preview.points;
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

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }
}
