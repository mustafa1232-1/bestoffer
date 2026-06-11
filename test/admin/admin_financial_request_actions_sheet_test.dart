import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/admin/models/admin_financial_request_model.dart';
import 'package:maslaki/features/admin/ui/widgets/admin_financial_request_actions_sheet.dart';
import 'package:maslaki/l10n/app_localizations.dart';

AdminFinancialRequestModel _request() {
  return const AdminFinancialRequestModel(
    id: 77,
    merchantId: 9,
    merchantName: 'Basmaya Store',
    requestType: 'app_pays_store',
    paymentScope: 'all',
    status: 'pending',
    amount: 0,
    requestedAmount: 250000,
    paidAmount: 0,
    isLocked: false,
  );
}

Widget _app() {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: AdminFinancialRequestActionsSheet(request: _request()),
    ),
  );
}

void main() {
  testWidgets('mark paid shows inline amount validation error', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app());

    final markPaidButton = find.widgetWithText(
      ElevatedButton,
      l10n.adminFinancialActionMarkPaid,
    );
    await tester.ensureVisible(markPaidButton);
    await tester.tap(markPaidButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.validationRequiredField(l10n.adminFinancialActionPaidAmount),
      ),
      findsOneWidget,
    );
  });
}
