import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/courier_pages.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi({required this.reports}) : super(Dio());

  final Map<String, dynamic> reports;

  @override
  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> analytics({
    bool skipTerminalSessionInvalidation = false,
  }) async => const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async => reports;

  @override
  Future<List<dynamic>> requestsV2({
    int limit = 40,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async => const <dynamic>[];

  @override
  Future<Map<String, dynamic>> competitionsV2({
    String scope = 'active',
    bool skipTerminalSessionInvalidation = false,
  }) async => const <String, dynamic>{'competitions': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> competitionProgressV2({
    bool skipTerminalSessionInvalidation = false,
  }) async => const <String, dynamic>{'items': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> competitionAchievementsSummaryV2({
    bool skipTerminalSessionInvalidation = false,
  }) async => const <String, dynamic>{'summary': <String, dynamic>{}};

  @override
  Future<Map<String, dynamic>> endDayReadiness({
    bool skipTerminalSessionInvalidation = false,
  }) async => const <String, dynamic>{
    'canEndDay': true,
    'openSettlements': <dynamic>[],
  };
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
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('courier reports page renders real period cards', (tester) async {
    final api = _FakeDeliveryApi(
      reports: {
        'summary': {
          'day': {
            'delivered_orders_count': 2,
            'delivery_fees': 3000,
            'service_fee_amount': 500,
            'commission_amount': 300,
            'store_net_received_amount': 8750,
            'app_due_from_delivery': 1500,
            'difference_amount': 50,
            'avg_rating': 4.8,
          },
          'week': {
            'delivered_orders_count': 10,
            'delivery_fees': 15000,
            'service_fee_amount': 2500,
            'commission_amount': 1200,
            'store_net_received_amount': 43250,
            'app_due_from_delivery': 5000,
            'difference_amount': 150,
            'avg_rating': 4.7,
          },
        },
      },
    );

    await tester.pumpWidget(_wrap(const CourierReportsPage(), api));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Today / اليوم'), findsOneWidget);
    expect(find.textContaining('Week / الأسبوع'), findsOneWidget);
    expect(find.textContaining('Service fee'), findsWidgets);
    expect(find.textContaining('Commission'), findsWidgets);
    expect(find.textContaining('App due'), findsWidgets);
    expect(find.textContaining('Differences'), findsWidgets);
  });
}
