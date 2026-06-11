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
  testWidgets('user login screen exposes user and service-provider registration actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LoginScreen()));
    await tester.pump();

    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('owner role login exposes owner registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.owner)),
    );
    await tester.pump();

    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('delivery role login does not expose registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.delivery)),
    );
    await tester.pump();

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('captain role login exposes captain registration action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const RoleLoginScreen(scope: RoleLoginScope.taxiCaptain)),
    );
    await tester.pump();

    expect(find.byType(TextButton), findsOneWidget);
  });
}
