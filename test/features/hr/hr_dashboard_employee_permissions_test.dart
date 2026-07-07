import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/hr/state/hr_controller.dart';
import 'package:maslaki/features/hr/ui/hr_dashboard_screen.dart';
import 'package:maslaki/features/notifications/state/notifications_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      token: 'test-token',
      user: UserModel(
        id: 1,
        fullName: 'HR User',
        phone: '07700000000',
        role: 'hr',
        block: 'A',
        buildingNumber: '10',
        apartment: '1',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'en',
        isSuperAdmin: false,
      ),
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeNotificationsController extends NotificationsController {
  _FakeNotificationsController(super.ref) {
    state = const NotificationsState();
  }

  @override
  Future<void> refreshUnreadCount() async {}

  @override
  void startRealtime() {}

  @override
  void stopRealtime() {}
}

class _FakeHrController extends HrController {
  _FakeHrController(super.ref) {
    state = const HrState(
      merchant: <String, dynamic>{'name': 'BestOffer Store'},
      stats: <String, dynamic>{},
      employees: <Map<String, dynamic>>[],
      attendance: <Map<String, dynamic>>[],
      payrollBatches: <Map<String, dynamic>>[],
      payrollItems: <Map<String, dynamic>>[],
      leaveRequests: <Map<String, dynamic>>[],
      salaryActions: <Map<String, dynamic>>[],
      advanceRequests: <Map<String, dynamic>>[],
      employeeActivityLogs: <Map<String, dynamic>>[],
      attendanceArchive: <Map<String, dynamic>>[],
    );
  }

  @override
  Future<void> bootstrap() async {}
}

void main() {
  testWidgets('HR employee dialog uses store permissions only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
          notificationsControllerProvider.overrideWith(
            (ref) => _FakeNotificationsController(ref),
          ),
          hrControllerProvider.overrideWith((ref) => _FakeHrController(ref)),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: HrDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Employees'));
    await tester.pumpAndSettle();

    final inviteButton = find.byIcon(Icons.person_add_alt_1_outlined);
    expect(inviteButton, findsOneWidget);
    await tester.ensureVisible(inviteButton);
    await tester.tap(inviteButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Invite employee'), findsOneWidget);
    expect(find.textContaining('Manage employees'), findsWidgets);
    expect(find.textContaining('View service requests'), findsNothing);
    expect(find.textContaining('Create services'), findsNothing);
  });
}
