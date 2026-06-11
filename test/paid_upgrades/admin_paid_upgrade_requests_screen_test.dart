import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/paid_upgrades/data/paid_upgrades_api.dart';
import 'package:maslaki/features/paid_upgrades/ui/admin_paid_upgrade_requests_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakePaidUpgradesApi extends PaidUpgradesApi {
  _FakePaidUpgradesApi() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> listAdminRequests({
    String status = 'pending_admin_review',
    String? planCode,
    int limit = 30,
    int offset = 0,
  }) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 11,
        'user_id': 90,
        'plan_id': 7,
        'plan_title': 'Premium',
        'plan_code': 'premium_monthly',
        'user_full_name': 'Test User',
        'user_phone': '07700000000',
        'status': 'pending_admin_review',
        'monthly_fee_iqd': 25000,
        'currency': 'IQD',
      },
    ];
  }

  @override
  Future<void> approveRequest(int requestId, {String? reviewNote}) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/admin/paid-upgrades/requests'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/admin/paid-upgrades/requests/$requestId/approve',
        ),
        statusCode: 400,
        data: <String, dynamic>{
          'message': 'VALIDATION_ERROR',
          'fields': <String, String>{'reviewNote': 'TOO_LONG'},
        },
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      paidUpgradesApiProvider.overrideWithValue(_FakePaidUpgradesApi()),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminPaidUpgradeRequestsScreen(),
    ),
  );
}

void main() {
  testWidgets('approve dialog shows inline backend note error', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final approveText = find.text(l10n.adminPaidUpgradeRequestsApproveAction);
    await tester.scrollUntilVisible(
      approveText,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(approveText);
    await tester.tap(approveText, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ok');
    await tester.tap(find.text(l10n.commonConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationTextTooLong), findsOneWidget);
  });
}
