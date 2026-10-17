import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/data/mimo_known_accounts.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/presentation/widgets/mimo_character.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/coupons/data/coupons_api.dart';
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

class _FakeCouponsApi extends CouponsApi {
  _FakeCouponsApi(this.coupons) : super(Dio());

  final List<Map<String, dynamic>> coupons;

  @override
  Future<List<Map<String, dynamic>>> listMyCoupons({
    int? merchantId,
    int limit = 80,
  }) async => coupons;
}

/// Rejects the first [failures] attempts as wrong PINs, then succeeds —
/// running the screen's pre-commit hook exactly like the real controller.
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
      state = const AuthState(
        error: 'رقم الهاتف أو الرمز السري غير صحيح',
        errorCode: 'INVALID_CREDENTIALS',
      );
      return;
    }
    final user = UserModel(
      id: 7,
      fullName: 'مصطفى سالم',
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
    );
    final hook = beforeLoginCommit;
    if (hook != null) {
      hookCalls++;
      await hook(user);
    }
    state = AuthState(user: user, token: 'token');
  }
}

Future<_ScriptedAuthController> _pumpLogin(
  WidgetTester tester, {
  int failures = 0,
  List<Map<String, dynamic>> coupons = const [],
  SecureStore? store,
}) async {
  late _ScriptedAuthController auth;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) {
          auth = _ScriptedAuthController(ref, failures: failures);
          return auth;
        }),
        appSettingsControllerProvider.overrideWith(
          (ref) => _FakeSettingsController(),
        ),
        couponsApiProvider.overrideWithValue(_FakeCouponsApi(coupons)),
        if (store != null) secureStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: LoginScreen(),
      ),
    ),
  );
  await tester.pump();
  return auth;
}

MimoCharacter _mimo(WidgetTester tester) =>
    tester.widget<MimoCharacter>(find.byType(MimoCharacter));

Future<void> _attempt(WidgetTester tester, String pin) async {
  await tester.enterText(find.byType(TextField).at(1), pin);
  await tester.tap(find.byType(ElevatedButton));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    debugResetLoginLock();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('unknown number: shocked → angry → hacked run + 1 min lock', (
    tester,
  ) async {
    final auth = await _pumpLogin(tester, failures: 3);
    expect(_mimo(tester).mood, MimoMood.idle);

    final fields = find.byType(TextField);
    await tester.tap(fields.at(0));
    await tester.pump();
    expect(_mimo(tester).mood, MimoMood.down);
    final lookBefore = _mimo(tester).lookX;
    await tester.enterText(fields.at(0), '07701234567');
    await tester.pump(const Duration(milliseconds: 300));
    expect(_mimo(tester).lookX, greaterThan(lookBefore));

    await _attempt(tester, '1111');
    expect(_mimo(tester).mood, MimoMood.shocked);
    expect(find.text('منو انت؟'), findsWidgets);

    await _attempt(tester, '2222');
    expect(_mimo(tester).mood, MimoMood.angry);
    expect(find.text('منو انت؟!'), findsWidgets);

    await _attempt(tester, '3333');
    // Animations are off in tests, so the run is skipped straight to laughing.
    expect(_mimo(tester).mood, MimoMood.laughing);
    expect(
      find.textContaining('مثلكي لا يمكن اختراقه'),
      findsWidgets,
    );
    expect(find.textContaining('حاول بعد'), findsOneWidget);
    final pinField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(pinField.enabled, isFalse);

    // Locked: tapping login does nothing.
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(auth.attempts, 3);

    // After a minute the PIN can be typed again.
    await tester.pump(const Duration(seconds: 61));
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).enabled,
      isTrue,
    );
  });

  testWidgets('number known on this device: Mimo greets by first name', (
    tester,
  ) async {
    final store = SecureStore();
    await tester.runAsync(
      () => MimoKnownAccounts(store).remember('07701234567', 'مصطفى سالم'),
    );
    await _pumpLogin(tester, failures: 2, store: store);

    await tester.enterText(find.byType(TextField).at(0), '07701234567');
    // Let the debounced on-device name lookup finish.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await _attempt(tester, '1111');
    expect(find.text('هلو مصطفى!'), findsWidgets);
    expect(find.textContaining('نثيت الرمز'), findsWidgets);

    await _attempt(tester, '2222');
    expect(_mimo(tester).mood, MimoMood.shocked);
    expect(find.textContaining('انت مصطفى لو لا؟'), findsWidgets);
  });

  testWidgets('customer sign-in: Mimo offers the public coupon first', (
    tester,
  ) async {
    final auth = await _pumpLogin(
      tester,
      coupons: [
        {
          'code': 'SHOP5',
          'discount_type': 'fixed',
          'discount_value': 5000,
          'scope_kind': 'merchant',
        },
        {
          'code': 'MIMO10',
          'discount_type': 'percent',
          'discount_value': '10.00',
          'scope_kind': 'global',
        },
      ],
    );
    await tester.enterText(find.byType(TextField).at(0), '07701234567');
    await _attempt(tester, '1234');

    expect(auth.hookCalls, 1);
    expect(auth.state.isAuthed, isFalse, reason: 'waits on the coupon');
    expect(_mimo(tester).mood, MimoMood.love);
    expect(find.text('عمو مصطفى!'), findsWidgets);
    expect(find.textContaining('التثوق من مثلكي'), findsWidgets);
    expect(find.text('MIMO10'), findsOneWidget);
    expect(find.text('خصم 10%'), findsOneWidget);

    await tester.tap(find.text('يلا نتسوق'));
    await tester.pump();
    await tester.pump();
    expect(auth.state.isAuthed, isTrue);
  });

  testWidgets('showing the PIN makes Mimo close his eyes', (tester) async {
    await _pumpLogin(tester);
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    expect(_mimo(tester).mood, MimoMood.down);
    await tester.tap(find.byIcon(Icons.visibility_rounded));
    await tester.pump();
    expect(_mimo(tester).mood, MimoMood.closed);
  });

  testWidgets('empty submit makes Mimo sad without calling the server', (
    tester,
  ) async {
    final auth = await _pumpLogin(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(_mimo(tester).mood, MimoMood.sad);
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
