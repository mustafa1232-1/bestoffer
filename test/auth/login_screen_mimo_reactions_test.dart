import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/presentation/widgets/mimo_character.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeSettingsController extends AppSettingsController {
  _FakeSettingsController() : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('ar'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

/// Rejects the first [failures] attempts, then succeeds — running the
/// screen's pre-commit hook exactly like the real controller does.
class _ScriptedAuthController extends AuthController {
  _ScriptedAuthController(super.ref, {required this.failures});

  final int failures;
  int attempts = 0;
  int hookCalls = 0;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> login(String phone, String pin) async {
    attempts++;
    if (attempts <= failures) {
      state = const AuthState(error: 'رقم الهاتف أو الرمز السري غير صحيح');
      return;
    }
    final hook = beforeLoginCommit;
    if (hook != null) {
      hookCalls++;
      await hook();
    }
    state = AuthState(
      user: UserModel(
        id: 7,
        fullName: 'Customer',
        phone: phone,
        role: 'user',
        block: 'A1',
        buildingNumber: '3',
        apartment: '9',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: false,
      ),
      token: 'token',
    );
  }
}

Widget _app(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

MimoMood _mood(WidgetTester tester) =>
    tester.widget<MimoCharacter>(find.byType(MimoCharacter)).mood;

void main() {
  testWidgets('Mimo reacts: typing → shocked → angry → relieved', (
    tester,
  ) async {
    late _ScriptedAuthController auth;
    await tester.pumpWidget(
      _app(
        const LoginScreen(),
        overrides: [
          authControllerProvider.overrideWith((ref) {
            auth = _ScriptedAuthController(ref, failures: 2);
            return auth;
          }),
          appSettingsControllerProvider.overrideWith(
            (ref) => _FakeSettingsController(),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(_mood(tester), MimoMood.idle);

    final fields = find.byType(TextField);
    await tester.tap(fields.at(0));
    await tester.pump();
    expect(_mood(tester), MimoMood.down);
    final lookBefore = tester
        .widget<MimoCharacter>(find.byType(MimoCharacter))
        .lookX;
    await tester.enterText(fields.at(0), '07701234567');
    await tester.pump();
    final lookAfter = tester
        .widget<MimoCharacter>(find.byType(MimoCharacter))
        .lookX;
    expect(lookAfter, greaterThan(lookBefore), reason: 'eyes follow caret');

    await tester.enterText(fields.at(1), '1111');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(_mood(tester), MimoMood.shocked);
    expect(find.text('منو انت؟'), findsWidgets);
    expect(find.text('رقم الهاتف أو الرمز السري غير صحيح'), findsOneWidget);

    await tester.enterText(fields.at(1), '2222');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(_mood(tester), MimoMood.angry);
    expect(find.text('منو انت؟!'), findsWidgets);

    await tester.enterText(fields.at(1), '1234');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(auth.hookCalls, 1);
    expect(_mood(tester), MimoMood.relieved);
    expect(find.text('لقد أخفتني!'), findsWidgets);
    expect(auth.state.isAuthed, isTrue);
  });

  testWidgets('showing the PIN makes Mimo close his eyes', (tester) async {
    await tester.pumpWidget(
      _app(
        const LoginScreen(),
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _ScriptedAuthController(ref, failures: 0),
          ),
          appSettingsControllerProvider.overrideWith(
            (ref) => _FakeSettingsController(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    expect(_mood(tester), MimoMood.down);
    await tester.tap(find.byIcon(Icons.visibility_rounded));
    await tester.pump();
    expect(_mood(tester), MimoMood.closed);
  });

  testWidgets('empty submit makes Mimo sad without calling the server', (
    tester,
  ) async {
    late _ScriptedAuthController auth;
    await tester.pumpWidget(
      _app(
        const LoginScreen(),
        overrides: [
          authControllerProvider.overrideWith((ref) {
            auth = _ScriptedAuthController(ref, failures: 0);
            return auth;
          }),
          appSettingsControllerProvider.overrideWith(
            (ref) => _FakeSettingsController(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(_mood(tester), MimoMood.sad);
    expect(auth.attempts, 0);
  });

  test('svgPath parses absolute, relative and arc commands', () {
    final path = svgPath(
      'M100 44 C93 36 84 29 84 20 A16 16 0 1 1 116 20 Z '
      'M26 50 l3 8 8 3 -8 3z',
    );
    final b = path.getBounds();
    expect(b.left, closeTo(26, 0.5));
    expect(b.right, closeTo(116, 0.5));
    expect(b.top, closeTo(4, 0.5));
    expect(b.bottom, closeTo(64, 0.5));
  });
}
