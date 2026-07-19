import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/company/data/company_api.dart';
import 'package:maslaki/features/company/models/company_models.dart';
import 'package:maslaki/features/company/ui/company_promotions_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeCompanyApi extends CompanyApi {
  _FakeCompanyApi() : super(Dio());

  @override
  Future<List<CompanyBranch>> branches(int companyId) async {
    return const <CompanyBranch>[];
  }

  @override
  Future<List<CompanyCoupon>> coupons(int companyId) async {
    return <CompanyCoupon>[
      CompanyCoupon.fromJson(<String, dynamic>{
        'id': 1,
        'code': 'COMPANY50',
        'discount_type': 'percent',
        'discount_value': 50,
        'company_applies_to_all_branches': true,
        'is_active': true,
        'coupon_status': 'active',
        'valid_until': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'targets': const <Map<String, dynamic>>[],
      }),
      CompanyCoupon.fromJson(<String, dynamic>{
        'id': 2,
        'code': 'COMPANYEX',
        'discount_type': 'fixed',
        'discount_value': 2000,
        'company_applies_to_all_branches': false,
        'is_active': true,
        'coupon_status': 'expired',
        'valid_until': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'targets': const <Map<String, dynamic>>[],
      }),
    ];
  }

  @override
  Future<List<CompanyCampaign>> campaigns(int companyId) async {
    return const <CompanyCampaign>[];
  }
}

Widget _app() {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: CompanyPromotionsScreen(api: _FakeCompanyApi(), companyId: 1),
  );
}

void main() {
  testWidgets('company promotions screen shows coupon lifecycle status', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsWidgets);
    expect(find.text('Expired'), findsWidgets);
    expect(find.textContaining('Valid until'), findsWidgets);
  });
}
