import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('taxi map uses one dark OpenStreetMap layer without keyed CARTO', () {
    final source = File('lib/pages/map_page.dart').readAsStringSync();

    expect(
      source,
      contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
    );
    expect(source, isNot(contains('basemaps.cartocdn.com')));
    expect(source, contains('© OpenStreetMap contributors'));
    expect(
      'backgroundColor: const Color(0xFF111A28)'.allMatches(source).length,
      1,
    );
    expect('tileBuilder:'.allMatches(source).length, 1);
    expect('ColorFilter.matrix'.allMatches(source).length, 1);
    expect(
      source,
      contains('tileBuilder: (_, tileWidget, _) => ColorFiltered('),
    );
    expect(
      source,
      isNot(contains('tileBuilder: (_, tileWidget, __) => ColorFiltered(')),
    );
  });
}
