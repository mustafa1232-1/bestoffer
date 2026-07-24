import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

/// Strings that must NEVER appear in a user-facing widget tree.
const List<String> _forbiddenTechnicalStrings = <String>[
  'DioException',
  'SESSION_RECOVERY_REQUIRED',
  'BOTTOM OVERFLOWED',
  'status code',
  'request ID',
  'تعذر تحميل الستوري',
  'تعذر تحميل منشورات مسلكي',
];

class _FakeSettingsController extends AppSettingsController {
  _FakeSettingsController() : super(SecureStore(), storageScope: 'test') {
    state = const AppSettingsState(
      locale: Locale('ar'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

/// Auth controller seeded with a raw backend error code, to prove the login
/// screen refuses to render it.
class _LeakingAuthController extends AuthController {
  _LeakingAuthController(super.ref) {
    state = const AuthState(error: 'SESSION_RECOVERY_REQUIRED');
  }

  @override
  Future<void> bootstrap() async {}
}

class _IdleAuthController extends AuthController {
  _IdleAuthController(super.ref);

  @override
  Future<void> bootstrap() async {}
}

Widget _app(
  Widget child, {
  required List<Override> overrides,
  MediaQueryData Function(MediaQueryData base)? mediaQuery,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) {
          if (mediaQuery == null) return child;
          return MediaQuery(
            data: mediaQuery(MediaQuery.of(context)),
            child: child,
          );
        },
      ),
    ),
  );
}

void _expectNoTechnicalStrings(WidgetTester tester) {
  for (final forbidden in _forbiddenTechnicalStrings) {
    expect(
      find.textContaining(forbidden, findRichText: true),
      findsNothing,
      reason: 'Login screen must not render the technical string "$forbidden".',
    );
  }
}

void main() {
  testWidgets(
    'login screen never renders a raw backend error code',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const LoginScreen(),
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _LeakingAuthController(ref),
            ),
            appSettingsControllerProvider.overrideWith(
              (ref) => _FakeSettingsController(),
            ),
          ],
        ),
      );
      await tester.pump();

      _expectNoTechnicalStrings(tester);
    },
  );

  testWidgets(
    'login screen does not overflow on a small phone with the keyboard open',
    (tester) async {
      // Small phone viewport (iPhone SE class) at 1x for simple math.
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          const LoginScreen(),
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _IdleAuthController(ref),
            ),
            appSettingsControllerProvider.overrideWith(
              (ref) => _FakeSettingsController(),
            ),
          ],
          // Simulate an open numeric keyboard eating the bottom inset.
          mediaQuery: (base) =>
              base.copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
        ),
      );
      await tester.pump();

      // A RenderFlex overflow surfaces here as a captured exception.
      expect(
        tester.takeException(),
        isNull,
        reason: 'Login card must scroll under the keyboard, not overflow.',
      );
      _expectNoTechnicalStrings(tester);

      // The phone field and the primary sign-in button remain reachable via
      // scrolling (no clipped/hidden required controls).
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsOneWidget);
    },
  );
}
