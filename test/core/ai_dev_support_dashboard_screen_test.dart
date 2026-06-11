import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/ai_dev_support/models/ops_action.dart';
import 'package:maslaki/features/ai_dev_support/models/ops_incident.dart';
import 'package:maslaki/features/ai_dev_support/models/ops_status.dart';
import 'package:maslaki/features/ai_dev_support/screens/ai_dev_support_dashboard_screen.dart';
import 'package:maslaki/features/ai_dev_support/screens/pending_approvals_screen.dart';
import 'package:maslaki/features/ai_dev_support/services/ai_dev_support_api.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeAiDevSupportApi extends AiDevSupportApi {
  _FakeAiDevSupportApi({
    this.incidentItems = const <OpsIncident>[],
    this.pending = const <OpsAction>[],
  }) : super(Dio());

  final List<OpsIncident> incidentItems;
  final List<OpsAction> pending;

  @override
  Future<OpsStatus> status() async {
    return const OpsStatus(
      overview: OpsStatusOverview(
        openIncidents: 2,
        sev1Open: 1,
        sev2Open: 1,
        pendingApprovals: 1,
      ),
      integrations: {
        'sentry': {'enabled': true},
        'datadog': {'enabled': true},
        'railway': {'enabled': true},
        'github': {'enabled': true},
        'openai': {'enabled': true},
      },
      release: {'version': '1.0.0'},
    );
  }

  @override
  Future<List<OpsIncident>> incidents({
    String severity = 'all',
    String status = 'all',
    String source = 'all',
    String affectedModule = 'all',
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    return incidentItems;
  }

  @override
  Future<List<OpsAction>> pendingActions() async {
    return pending;
  }

  @override
  Future<Map<String, dynamic>> approveAction({
    required int incidentId,
    int? actionId,
    String confirmationText = '',
    String? comment,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> rejectAction({
    required int incidentId,
    String? reason,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> getSettings() async {
    return {
      'settings': {
        'ai_analysis_enabled': true,
        'sentry_webhook_enabled': true,
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> auditLogs({int? incidentId}) async {
    return const <Map<String, dynamic>>[];
  }
}

UserModel _user({required bool superAdmin}) {
  return UserModel(
    id: 1,
    fullName: 'Admin User',
    phone: '07700000000',
    role: superAdmin ? 'admin' : 'user',
    block: 'A',
    buildingNumber: '1',
    apartment: '1',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    isSuperAdmin: superAdmin,
  );
}

void main() {
  testWidgets('AI DEV SUPPORT dashboard renders for super admin', (tester) async {
    final fakeApi = _FakeAiDevSupportApi(
      incidentItems: [
        const OpsIncident(
          id: 101,
          source: 'sentry',
          severity: 'SEV1',
          status: 'open',
          riskLevel: 'critical',
          title: 'Crash in checkout',
          symptoms: <dynamic>['crash'],
          evidence: <dynamic>['trace'],
        ),
      ],
      pending: [
        const OpsAction(
          id: 7,
          incidentId: 101,
          actionType: 'restart_service',
          riskLevel: 'high',
          status: 'pending_approval',
          input: <String, dynamic>{},
          output: <String, dynamic>{},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              ref,
              AuthState(user: _user(superAdmin: true), token: 'token'),
            ),
          ),
          aiDevSupportApiProvider.overrideWithValue(fakeApi),
        ],
        child: const MaterialApp(home: AiDevSupportDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI DEV SUPPORT'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Incidents'), findsOneWidget);
    expect(find.text('Pending Approvals'), findsWidgets);
  });

  testWidgets('AI DEV SUPPORT dashboard blocks non super admin', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              ref,
              AuthState(user: _user(superAdmin: false), token: 'token'),
            ),
          ),
          aiDevSupportApiProvider.overrideWithValue(_FakeAiDevSupportApi()),
        ],
        child: const MaterialApp(home: AiDevSupportDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Access denied'), findsOneWidget);
  });

  testWidgets('Pending approvals asks for typed confirmation on critical/high', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiDevSupportApiProvider.overrideWithValue(
            _FakeAiDevSupportApi(
              pending: const [
                OpsAction(
                  id: 1,
                  incidentId: 10,
                  actionType: 'rollback_service',
                  riskLevel: 'critical',
                  status: 'pending_approval',
                  input: <String, dynamic>{},
                  output: <String, dynamic>{},
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: PendingApprovalsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm critical action'), findsOneWidget);
    expect(find.textContaining('Type APPROVE'), findsOneWidget);
  });

  testWidgets('AI DEV SUPPORT renders in RTL direction', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              ref,
              AuthState(user: _user(superAdmin: true), token: 'token'),
            ),
          ),
          aiDevSupportApiProvider.overrideWithValue(_FakeAiDevSupportApi()),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AiDevSupportDashboardScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(Directionality), findsWidgets);
    expect(find.text('AI DEV SUPPORT'), findsOneWidget);
  });
}
