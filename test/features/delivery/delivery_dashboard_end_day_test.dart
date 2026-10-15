import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/delivery_dashboard_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi({required this.readiness}) : super(Dio());

  final Map<String, dynamic> readiness;

  int readinessCalls = 0;
  int ordersCalls = 0;
  int analyticsCalls = 0;
  int dashboardCalls = 0;
  int reportsCalls = 0;
  int requestsCalls = 0;
  int activeCompetitionsCalls = 0;
  int historyCompetitionsCalls = 0;
  int competitionProgressCalls = 0;
  int achievementsCalls = 0;

  @override
  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    ordersCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> analytics({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    analyticsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    dashboardCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    reportsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<List<dynamic>> requestsV2({
    int limit = 40,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    requestsCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> competitionsV2({
    String scope = 'active',
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (scope == 'history') {
      historyCompetitionsCalls += 1;
    } else {
      activeCompetitionsCalls += 1;
    }
    return const <String, dynamic>{'competitions': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionProgressV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    competitionProgressCalls += 1;
    return const <String, dynamic>{'items': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionAchievementsSummaryV2({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    achievementsCalls += 1;
    return const <String, dynamic>{'summary': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> endDayReadiness({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    readinessCalls += 1;
    return readiness;
  }

  @override
  Future<Map<String, dynamic>> deliveryEarnings() async => const {
    'todayEarnings': 0,
    'monthEarnings': 0,
    'completedTodayCount': 0,
    'completedMonthCount': 0,
    'rows': <dynamic>[],
  };
}

Widget _wrap(
  Widget child,
  DeliveryApi api, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(
      (ref) => _FakeAuthController(ref, const AuthState(token: 'test-token')),
    ),
    deliveryApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.dark(),
    home: child,
  ),
);

void main() {
  testWidgets(
    'delivery home stays focused and skips extended dashboard calls',
    (tester) async {
      final api = _FakeDeliveryApi(
        readiness: const {
          'canEndDay': false,
          'outstandingAmount': 1500,
          'openSettlements': [
            {
              'id': 1,
              'appDueFromDelivery': 1500,
              'settlementStatus': 'pending_store_confirmation',
              'status': 'pending',
            },
          ],
        },
      );

      await tester.pumpWidget(_wrap(const DeliveryDashboardScreen(), api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('delivery_home_current')), findsOneWidget);
      expect(find.byKey(const Key('delivery_home_completed')), findsOneWidget);
      expect(
        find.byKey(const Key('delivery_home_today_earnings')),
        findsOneWidget,
      );
      expect(find.text('Current orders'), findsOneWidget);
      expect(find.text('Completed orders'), findsOneWidget);
      expect(find.text('Today earnings'), findsOneWidget);
      expect(find.textContaining('You cannot close the day yet'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(api.readinessCalls, 0);
      expect(api.reportsCalls, 0);
      expect(api.activeCompetitionsCalls, 0);
      expect(api.historyCompetitionsCalls, 0);
      expect(api.competitionProgressCalls, 0);
      expect(api.achievementsCalls, 0);
    },
  );

  testWidgets('delivery home cards open their real destinations', (
    tester,
  ) async {
    final api = _FakeDeliveryApi(
      readiness: const {'canEndDay': true, 'openSettlements': <dynamic>[]},
    );

    Future<void> openHome() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_wrap(const DeliveryDashboardScreen(), api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await openHome();
    await tester.ensureVisible(find.byKey(const Key('delivery_home_current')));
    await tester.tap(find.byKey(const Key('delivery_home_current')));
    await tester.pump();
    expect(find.byKey(const Key('delivery_home_current')), findsNothing);
    expect(find.text('Current orders'), findsWidgets);

    await openHome();
    await tester.ensureVisible(
      find.byKey(const Key('delivery_home_completed')),
    );
    await tester.tap(find.byKey(const Key('delivery_home_completed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delivery_home_completed')), findsNothing);
    expect(find.text('Completed orders'), findsOneWidget);

    await openHome();
    await tester.ensureVisible(
      find.byKey(const Key('delivery_home_today_earnings')),
    );
    await tester.tap(find.byKey(const Key('delivery_home_today_earnings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delivery_home_today_earnings')), findsNothing);
    expect(find.text('Delivery earnings'), findsOneWidget);
  });

  testWidgets('delivery home fits a narrow Arabic phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeDeliveryApi(
      readiness: const {'canEndDay': true, 'openSettlements': <dynamic>[]},
    );
    await tester.pumpWidget(
      _wrap(const DeliveryDashboardScreen(), api, locale: const Locale('ar')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('الطلبات الحالية'), findsOneWidget);
    expect(find.text('الطلبات المنتهية'), findsOneWidget);
    expect(find.text('أرباح اليوم'), findsOneWidget);
    expect(find.text('ذمة التطبيق'), findsOneWidget);
    expect(find.text('تسويات مفتوحة'), findsOneWidget);
    expect(find.text('أرباح الشهر'), findsOneWidget);
    expect(find.text('الطلبات الملغية'), findsOneWidget);
    expect(find.text('إجمالي الطلبات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
