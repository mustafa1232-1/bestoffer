import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStore extends SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value ? '1' : '0';
  }

  @override
  Future<bool?> readBool(String key) async {
    final raw = _values[key];
    if (raw == null) return null;
    if (raw == '1') return true;
    if (raw == '0') return false;
    return null;
  }
}

void main() {
  group('AppSettingsController locale bootstrap', () {
    test('stored locale wins over device locale', () async {
      final store = _FakeSecureStore();
      await store.writeString('app_locale', 'en');
      final controller = AppSettingsController(
        store,
        deviceLocale: const Locale('ar'),
      );

      await controller.bootstrap();

      expect(controller.state.locale.languageCode, 'en');
      expect(controller.state.loaded, isTrue);
    });

    test('supported device locale is used on first launch', () async {
      final controller = AppSettingsController(
        _FakeSecureStore(),
        deviceLocale: const Locale('en'),
      );

      await controller.bootstrap();

      expect(controller.state.locale.languageCode, 'en');
    });

    test('unsupported device locale falls back to arabic', () async {
      final controller = AppSettingsController(
        _FakeSecureStore(),
        deviceLocale: const Locale('fr'),
      );

      await controller.bootstrap();

      expect(controller.state.locale.languageCode, 'ar');
    });
  });
}
