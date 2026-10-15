import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/widgets/app_user_drawer.dart';
import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_support_tickets_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'staff with support read permission opens admin support tickets',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(ref, _staffAuthState()),
            ),
            adminApiProvider.overrideWithValue(
              _FakeAdminApi(canReadSupportTickets: true),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AppUserDrawer(
                title: 'Menu',
                embedded: true,
                showSettings: false,
                showProfileButton: false,
                showCommunitySection: false,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.forum_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AdminSupportTicketsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'staff without support read permission does not get admin tickets',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(ref, _staffAuthState()),
            ),
            adminApiProvider.overrideWithValue(
              _FakeAdminApi(canReadSupportTickets: false),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AppUserDrawer(
                title: 'Menu',
                embedded: true,
                showSettings: false,
                showProfileButton: false,
                showCommunitySection: false,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.forum_outlined), findsNothing);
    },
  );
}

AuthState _staffAuthState() {
  return AuthState(
    token: 'staff-token',
    user: UserModel(
      id: 81,
      fullName: 'Support Staff',
      phone: '07790000000',
      role: 'staff',
      block: 'A1',
      buildingNumber: '3',
      apartment: '9',
      imageUrl: null,
      workTitle: null,
      workCompany: null,
      preferredLocale: 'ar',
      isSuperAdmin: false,
    ),
  );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> logout() async {}
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi({required this.canReadSupportTickets}) : super(Dio());

  final bool canReadSupportTickets;

  @override
  Future<Map<String, dynamic>> myPermissions() async {
    return {
      'wildcard': false,
      'permissions': [
        if (canReadSupportTickets)
          {'key': 'support.tickets.read', 'scope': 'all'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> supportTickets({
    String? status,
    String? domain,
    String? search,
    int limit = 25,
    int offset = 0,
  }) async {
    return {'items': <Map<String, dynamic>>[], 'total': 0};
  }

  @override
  Future<Map<String, dynamic>> supportSupervisorOverview() async {
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> supportKpis({
    String? from,
    String? to,
    String? team,
  }) async {
    return const <String, dynamic>{};
  }
}
