import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/coupons/data/coupons_api.dart';
import 'package:maslaki/features/coupons/ui/coupon_management_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeCouponsApi extends CouponsApi {
  _FakeCouponsApi({
    List<Map<String, dynamic>>? coupons,
  })  : _coupons = coupons ?? const [],
        super(Dio());

  final List<Map<String, dynamic>> _coupons;

  @override
  Future<List<Map<String, dynamic>>> listCoupons({
    bool activeOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    if (!activeOnly) return _coupons;
    return _coupons.where((coupon) {
      final status =
          '${coupon['coupon_status'] ?? coupon['couponStatus'] ?? coupon['status'] ?? ''}'
              .trim()
              .toLowerCase();
      if (status.isNotEmpty) return status == 'active';
      return coupon['is_active'] == true || coupon['isActive'] == true;
    }).toList(growable: false);
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
      couponsApiProvider.overrideWithValue(
        _FakeCouponsApi(
          coupons: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'code': 'ACTIVE10',
              'description': 'Active coupon',
              'discount_type': 'percent',
              'discount_value': 10,
              'min_order_total': 0,
              'max_uses': null,
              'uses_count': 0,
              'valid_from': DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'valid_until': DateTime.now()
                  .add(const Duration(days: 1))
                  .toIso8601String(),
              'is_active': true,
              'coupon_status': 'active',
            },
            <String, dynamic>{
              'id': 2,
              'code': 'EXPIRED20',
              'description': 'Expired coupon',
              'discount_type': 'fixed',
              'discount_value': 20,
              'min_order_total': 0,
              'max_uses': null,
              'uses_count': 0,
              'valid_from': DateTime.now()
                  .subtract(const Duration(days: 5))
                  .toIso8601String(),
              'valid_until': DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'is_active': true,
              'coupon_status': 'expired',
            },
          ],
        ),
      ),
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

  testWidgets('coupon management shows lifecycle status and active-only filter', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 1600));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.textContaining('Active'), findsWidgets);
    expect(find.textContaining('Expired'), findsWidgets);

    await tester.tap(find.widgetWithText(
      SwitchListTile,
      l10n.couponManagementActiveOnly,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Expired'), findsNothing);
    expect(find.textContaining('Active'), findsWidgets);
  });
}
