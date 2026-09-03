import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('taxi map uses OpenStreetMap without the keyed CARTO basemap', () {
    final source = File('lib/pages/map_page.dart').readAsStringSync();

    expect(
      source,
      contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
    );
    expect(source, isNot(contains('basemaps.cartocdn.com')));
    expect(source, contains('© OpenStreetMap contributors'));
    expect(source, contains('backgroundColor: const Color(0xFF111A28)'));
    expect(source, contains('tileBuilder:'));
    expect(source, contains('ColorFilter.matrix'));
    expect(source, contains('backgroundColor: const Color(0xFF111A28)'));
    expect(source, contains('tileBuilder:'));
    expect(source, contains('ColorFilter.matrix'));
  });
}
