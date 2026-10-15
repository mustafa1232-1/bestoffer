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

    test('accepts existing staff account phone lengths for login', () {
      expect(isPlausibleAuthLoginPhone('07710111111'), isTrue);
      expect(isPlausibleAuthLoginPhone('077010111111'), isTrue);
      expect(isPlausibleAuthLoginPhone('07701'), isFalse);
      expect(isPlausibleAuthLoginPhone('0770101111111111'), isFalse);
    });

    test('keeps customer registration phone validation strict', () {
      expect(isPlausibleIraqiAuthPhone('07710111111'), isTrue);
      expect(isPlausibleIraqiAuthPhone('077010111111'), isFalse);
    });
  });
}
