import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/presentation/role_login_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

void main() {
  testWidgets(
    'user login screen exposes only customer registration',
    (tester) async {
      await tester.pumpWidget(_app(const LoginScreen()));
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LoginScreen)),
      );
      expect(
        find.widgetWithText(TextButton, l10n.authCreateUserAccount),
        findsOneWidget,
      );
      expect(find.text('إنشاء حساب صاحب خدمة'), findsNothing);
      expect(find.byType(TextButton), findsNWidgets(2));
    },
  );

  testWidgets('owner role login exposes owner registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.owner)),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(RoleLoginScreen)),
    );
    expect(
      find.widgetWithText(TextButton, l10n.authCreateOwnerAccount),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('delivery role login does not expose registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.delivery)),
    );
    await tester.pump();

    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('captain role login exposes captain registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.taxiCaptain)),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(RoleLoginScreen)),
    );
    expect(
      find.widgetWithText(TextButton, l10n.authTaxiCaptainAccount),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNWidgets(2));
  });
}
