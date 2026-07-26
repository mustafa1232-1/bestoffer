import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeSettingsController extends AppSettingsController {
  _FakeSettingsController() : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('en'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeAuthController extends AuthController {
  int logoutCalls = 0;

  _FakeAuthController(super.ref);

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> login(String phone, String pin) async {
    state = AuthState(
      user: UserModel(
        id: 92,
        fullName: 'Service Provider',
        phone: '07770000000',
        role: 'service_provider',
        block: 'A1',
        buildingNumber: '2',
        apartment: '8',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: false,
      ),
      token: 'service-provider-token',
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}

Widget _app(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

void main() {
  testWidgets(
    'service provider login stays authenticated without auto logout',
    (tester) async {
      late _FakeAuthController authController;

      await tester.pumpWidget(
        _app(
          const LoginScreen(),
          overrides: [
            authControllerProvider.overrideWith((ref) {
              authController = _FakeAuthController(ref);
              return authController;
            }),
            appSettingsControllerProvider.overrideWith(
              (ref) => _FakeSettingsController(),
            ),
          ],
        ),
      );
      await tester.pump();

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.at(0), '07770000000');
      await tester.enterText(textFields.at(1), '1234');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump(const Duration(milliseconds: 250));

      expect(authController.state.isServiceProvider, isTrue);
      expect(authController.logoutCalls, 0);
    },
  );
}
