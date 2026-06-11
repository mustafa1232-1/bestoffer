import 'package:maslaki/core/utils/parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localized numeric parsing', () {
    test('parses arabic-indic integers', () {
      expect(tryParseLocalizedInt('١٢٣٤٥'), 12345);
      expect(parseInt('١٢٣٤٥'), 12345);
    });

    test('parses eastern-arabic integers', () {
      expect(tryParseLocalizedInt('۱۲۳'), 123);
      expect(parseInt('۱۲۳'), 123);
    });

    test('parses localized doubles with separators', () {
      expect(tryParseLocalizedDouble('١٢٣٤٫٥'), 1234.5);
      expect(tryParseLocalizedDouble('1,250.75'), 1250.75);
      expect(parseDouble('١٬٢٥٠٫٧٥'), 1250.75);
    });

    test('returns null for invalid localized values', () {
      expect(tryParseLocalizedInt('abc'), isNull);
      expect(tryParseLocalizedDouble('--'), isNull);
    });
  });
}
