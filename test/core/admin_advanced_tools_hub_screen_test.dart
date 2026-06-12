import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/admin/ui/admin_advanced_tools_hub_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

UserModel _user({required String role, bool isSuperAdmin = false}) {
  return UserModel(
    id: 1,
    fullName: 'Test User',
    phone: '07700000000',
    role: role,
    block: 'A1',
    buildingNumber: 'A101',
    apartment: '101',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'ar',
    isSuperAdmin: isSuperAdmin,
  );
}

Future<void> _pumpHub(
  WidgetTester tester, {
  required AuthState authState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, authState),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminAdvancedToolsHubScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin sees company portal tool', (tester) async {
    await _pumpHub(
      tester,
      authState: AuthState(
        token: 'token',
        user: _user(role: 'admin'),
      ),
    );

    expect(find.text('Company portal'), findsOneWidget);
  });

  testWidgets('deputy admin does not see company portal tool', (tester) async {
    await _pumpHub(
      tester,
      authState: AuthState(
        token: 'token',
        user: _user(role: 'deputy_admin'),
      ),
    );

    expect(find.text('Company portal'), findsNothing);
  });
}
