import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/settings/ui/pages/settings_account_screen.dart';
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
  _FakeAuthController(super.ref, {this.deleteResult = true}) {
    state = AuthState(
      user: UserModel(
        id: 41,
        fullName: 'Review User',
        phone: '07700000041',
        role: 'user',
        block: 'A',
        buildingNumber: '1',
        apartment: '2',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'en',
        isSuperAdmin: false,
      ),
      token: 'review-token',
    );
  }

  final bool deleteResult;
  int deleteCalls = 0;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<bool> deleteAccount({String? reasonCode, String? note}) async {
    deleteCalls += 1;
    if (deleteResult) {
      state = const AuthState();
      return true;
    }
    state = state.copyWith(
      loading: false,
      error: 'Deletion failed on the server.',
    );
    return false;
  }
}

Widget _app({
  required Widget child,
  required _FakeAuthController Function(Ref ref) authFactory,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(authFactory),
      appSettingsControllerProvider.overrideWith(
        (ref) => _FakeSettingsController(),
      ),
    ],
    child: MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

void main() {
  testWidgets('delete account requires two explicit confirmations', (
    tester,
  ) async {
    late _FakeAuthController auth;
    await tester.pumpWidget(
      _app(
        child: const SettingsAccountScreen(),
        authFactory: (ref) {
          auth = _FakeAuthController(ref);
          return auth;
        },
      ),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.byIcon(Icons.delete_outline_rounded);
    await tester.scrollUntilVisible(
      deleteButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(auth.deleteCalls, 0);
    expect(find.text('Final confirmation'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, 'I understand, delete my account'),
    );
    await tester.pumpAndSettle();

    expect(auth.deleteCalls, 1);
    expect(auth.state.isAuthed, isFalse);
  });

  testWidgets(
    'delete account backend failure stays signed in and shows error',
    (tester) async {
      late _FakeAuthController auth;
      await tester.pumpWidget(
        _app(
          child: const SettingsAccountScreen(),
          authFactory: (ref) {
            auth = _FakeAuthController(ref, deleteResult: false);
            return auth;
          },
        ),
      );
      await tester.pumpAndSettle();

      final deleteButton = find.byIcon(Icons.delete_outline_rounded);
      await tester.scrollUntilVisible(
        deleteButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'I understand, delete my account'),
      );
      await tester.pumpAndSettle();

      expect(auth.deleteCalls, 1);
      expect(auth.state.isAuthed, isTrue);
      expect(find.text('Deletion failed on the server.'), findsOneWidget);
    },
  );
}
