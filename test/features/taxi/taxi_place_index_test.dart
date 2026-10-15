import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/features/taxi/data/taxi_place_index.dart';

void main() {
  group('searchTaxiPlaceIndex', () {
    test('returns several useful Karrada landmarks', () {
      final results = searchTaxiPlaceIndex('الكرادة');
      final titles = results.map((item) => item.title).toList();

      expect(results.length, greaterThanOrEqualTo(6));
      expect(titles, contains('الكرادة - ساحة الاندلس'));
      expect(titles, contains('الكرادة - كهرمانة'));
      expect(titles, contains('جامعة الاسراء'));
    });

    test('normalizes common Arabic spelling variants', () {
      final results = searchTaxiPlaceIndex('كراده');
      final titles = results.map((item) => item.title).toList();

      expect(titles, contains('الكرادة'));
      expect(titles, contains('كرادة داخل'));
    });

    test('supports English aliases', () {
      final results = searchTaxiPlaceIndex('karrada');
      final titles = results.map((item) => item.title).toList();

      expect(titles, contains('الكرادة'));
      expect(titles, contains('الكرادة - العرصات'));
    });

    test('finds category driven suggestions', () {
      final results = searchTaxiPlaceIndex('كافيه');
      final titles = results.map((item) => item.title).toList();

      expect(titles, contains('كافيهات الكرادة'));
      expect(results.length, greaterThanOrEqualTo(3));
    });

    test('finds useful university, hospital, mall, and airport results', () {
      final universities = searchTaxiPlaceIndex('جامعة');
      final hospitals = searchTaxiPlaceIndex('مستشفى');
      final malls = searchTaxiPlaceIndex('مول');
      final airport = searchTaxiPlaceIndex('مطار بغداد');

      expect(universities.map((item) => item.title), contains('جامعة بغداد'));
      expect(hospitals.map((item) => item.title), contains('مدينة الطب'));
      expect(malls.map((item) => item.title), contains('بغداد مول'));
      expect(airport.map((item) => item.title), contains('مطار بغداد الدولي'));
    });

    test('uses the geographic bias to prefer nearby matching places', () {
      final results = searchTaxiPlaceIndex(
        'مول',
        bias: const LatLng(33.3244, 44.4943),
      );

      expect(results, isNotEmpty);
      expect(results.first.title, 'زيونة مول');
    });
  });
}
