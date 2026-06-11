import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/company/data/company_api.dart';
import 'package:maslaki/features/company/models/company_models.dart';
import 'package:maslaki/features/company/ui/widgets/company_promotion_dialogs.dart';
import 'package:maslaki/l10n/app_localizations.dart';

CompanyBranch _branch() {
  return const CompanyBranch(
    id: 1,
    name: 'Branch A',
    type: 'store',
    description: null,
    phone: null,
    imageUrl: null,
    isOpen: true,
    isApproved: true,
    isDisabled: false,
    ownerFullName: null,
    ownerPhone: null,
    totalOrders: 0,
    completedOrders: 0,
    cancelledOrders: 0,
    activeOrders: 0,
    grossSales: 0,
    appDue: 0,
    totalCollected: 0,
    outstandingAmount: 0,
    trackedItems: 0,
    outOfStockItems: 0,
    lowStockItems: 0,
    inventoryEnabled: true,
    dailyUpdateMode: null,
    lastDailyCheckAt: null,
    lastInventoryUpdateAt: null,
    showAllWithoutAutoDisable: false,
    staleDailyCheck: false,
  );
}

Widget _app() {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: CompanyCreateCouponDialog(
        api: CompanyApi(Dio()),
        companyId: 1,
        branches: <CompanyBranch>[_branch()],
      ),
    ),
  );
}

void main() {
  testWidgets('coupon dialog shows inline code validation error', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app());

    await tester.tap(find.text(l10n.companyPromotionsCreateCoupon));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.validationRequiredField(l10n.companyPromotionsCouponCode)),
      findsOneWidget,
    );
  });
}
