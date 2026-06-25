import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/delivery_reports_screens.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi({required this.earnings, required this.ratings})
    : super(Dio());

  final Map<String, dynamic> earnings;
  final Map<String, dynamic> ratings;

  @override
  Future<Map<String, dynamic>> deliveryEarnings() async => earnings;

  @override
  Future<Map<String, dynamic>> deliveryRatings() async => ratings;
}

Widget _wrap(Widget child, DeliveryApi api) => ProviderScope(
  overrides: [deliveryApiProvider.overrideWithValue(api)],
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.dark(),
    home: child,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('earnings screen shows totals and per-order rows', (
    tester,
  ) async {
    final api = _FakeDeliveryApi(
      earnings: {
        'todayEarnings': 3000,
        'monthEarnings': 5000,
        'completedTodayCount': 1,
        'completedMonthCount': 2,
        'deliveryFeeSum': 5000,
        'rows': [
          {
            'orderId': 101,
            'orderNumber': 101,
            'customerName': 'Cust',
            'merchantName': 'Merch',
            'deliveredAt': '2026-06-15',
            'deliveryFee': 3000,
            'totalInvoice': 14000,
            'paymentMethod': 'cash',
            'status': 'delivered',
          },
        ],
      },
      ratings: const {'averageRating': 0, 'ratingCount': 0, 'rows': []},
    );

    await tester.pumpWidget(_wrap(const DeliveryEarningsScreen(), api));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('#101'), findsOneWidget);
    expect(find.textContaining('Merch'), findsOneWidget);
  });

  testWidgets('earnings screen shows an empty state (not a fake zero list)', (
    tester,
  ) async {
    final api = _FakeDeliveryApi(
      earnings: const {
        'todayEarnings': 0,
        'monthEarnings': 0,
        'completedTodayCount': 0,
        'completedMonthCount': 0,
        'rows': <dynamic>[],
      },
      ratings: const {'rows': <dynamic>[]},
    );

    await tester.pumpWidget(_wrap(const DeliveryEarningsScreen(), api));
    await _settle(tester);

    expect(find.text('No completed orders yet.'), findsOneWidget);
  });

  testWidgets('ratings screen shows rows linked to their orders', (
    tester,
  ) async {
    final api = _FakeDeliveryApi(
      earnings: const {'rows': <dynamic>[]},
      ratings: {
        'averageRating': 4.5,
        'ratingCount': 2,
        'rows': [
          {
            'ratingId': 201,
            'orderId': 201,
            'orderNumber': 201,
            'stars': 5,
            'comment': 'Great',
            'customerName': 'Cust',
            'merchantName': 'Merch',
            'createdAt': '2026-06-10',
          },
        ],
      },
    );

    await tester.pumpWidget(_wrap(const DeliveryRatingsScreen(), api));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('#201'), findsOneWidget);
    expect(find.text('Great'), findsOneWidget);
  });
}
