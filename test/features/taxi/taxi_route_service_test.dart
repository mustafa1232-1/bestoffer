import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';

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
}
