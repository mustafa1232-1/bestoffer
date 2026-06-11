import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/coupons/data/coupons_api.dart';
import 'package:maslaki/features/coupons/ui/coupon_management_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeCouponsApi extends CouponsApi {
  _FakeCouponsApi() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> listCoupons({
    bool activeOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> getCouponStats({
    int? merchantId,
    bool includeGlobal = true,
    int days = 30,
  }) async {
    return <String, dynamic>{
      'totals': <String, dynamic>{},
      'performance': <String, dynamic>{},
      'topCoupons': const <Map<String, dynamic>>[],
    };
  }
}

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      couponsApiProvider.overrideWithValue(_FakeCouponsApi()),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: CouponManagementScreen(mode: CouponManagerMode.owner),
    ),
  );
}

void main() {
  testWidgets('coupon management shows inline code validation error', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 1600));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final createButton = find.text(l10n.couponManagementCreateAction);
    await tester.ensureVisible(createButton);
    await tester.tap(createButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    final codeField = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      codeField.decoration?.errorText,
      l10n.validationRequiredField(l10n.couponManagementCodeLabel),
    );
  });
}
