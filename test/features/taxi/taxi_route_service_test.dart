import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('TaxiRouteService generates Waze and Google Maps URIs', () {
    final service = TaxiRouteService(dio: Dio());
    final destination = const LatLng(33.31456, 44.36611);

    expect(
      service.buildWazeAppUri(destination).toString(),
      'waze://?ll=33.31456,44.36611&navigate=yes',
    );
    expect(
      service.buildWazeWebUri(destination).toString(),
      'https://waze.com/ul?ll=33.31456,44.36611&navigate=yes',
    );
    expect(
      service.buildGoogleMapsUri(destination).toString(),
      'https://www.google.com/maps/search/?api=1&query=33.31456,44.36611',
    );
  });

  test('TaxiRouteService falls back to straight-line preview when OSRM fails', () async {
    final service = TaxiRouteService(dio: Dio()..httpClientAdapter = _ThrowingAdapter());
    final from = const LatLng(33.31456, 44.36611);
    final to = const LatLng(33.32091, 44.39118);

    final preview = await service.fetchDrivingRoutePreview(from: from, to: to);

    expect(preview.points, hasLength(2));
    expect(preview.points.first.latitude, from.latitude);
    expect(preview.points.first.longitude, from.longitude);
    expect(preview.points.last.latitude, to.latitude);
    expect(preview.points.last.longitude, to.longitude);
    expect(preview.durationSeconds, isNull);
    expect(preview.distanceMeters, greaterThan(0));
  });
}