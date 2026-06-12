import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_companies_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> companyAdminCompanies({
    int limit = 100,
    int offset = 0,
  }) async {
    return const {'companies': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> companyAdminPendingBranchRequests() async {
    return const {'requests': <dynamic>[]};
  }

  @override
  Future<List<dynamic>> merchants() async {
    return const <dynamic>[];
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

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AuthState authState,
  AdminApi? adminApi,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, authState),
        ),
        if (adminApi != null) adminApiProvider.overrideWithValue(adminApi),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminCompaniesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deputy admin sees forbidden state', (tester) async {
    await _pumpScreen(
      tester,
      authState: AuthState(
        token: 'token',
        user: _user(role: 'deputy_admin'),
      ),
    );

    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('admin loads company management shell', (tester) async {
    await _pumpScreen(
      tester,
      authState: AuthState(
        token: 'token',
        user: _user(role: 'admin'),
      ),
      adminApi: _FakeAdminApi(),
    );

    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
