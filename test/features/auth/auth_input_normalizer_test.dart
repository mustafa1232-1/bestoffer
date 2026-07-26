import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/domain/auth_input_normalizer.dart';

void main() {
  group('auth input normalizer', () {
    test('normalizes Iraqi phone formats to local mobile format', () {
      expect(normalizeIraqiPhoneForAuth('+964 770 000 0000'), '07700000000');
      expect(normalizeIraqiPhoneForAuth('9647700000000'), '07700000000');
      expect(normalizeIraqiPhoneForAuth('7700000000'), '07700000000');
      expect(normalizeIraqiPhoneForAuth('07700000000'), '07700000000');
    });

    test('preserves PIN leading zeroes while normalizing Arabic digits', () {
      expect(normalizeAuthPin('٠٠١٢'), '0012');
      expect(normalizeAuthPin(' ۰۰۹۹ '), '0099');
    });

    test('does not rewrite unrecognized international numbers as Iraqi', () {
      expect(normalizeIraqiPhoneForAuth('+15551234567'), '+15551234567');
    });
  });
}
