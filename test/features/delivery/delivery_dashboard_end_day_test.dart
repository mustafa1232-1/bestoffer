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
  }) async {
    ordersCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> analytics() async {
    analyticsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    dashboardCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> reportsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    reportsCalls += 1;
    return const <String, dynamic>{};
  }

  @override
  Future<List<dynamic>> requestsV2({int limit = 40, int offset = 0}) async {
    requestsCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> competitionsV2({String scope = 'active'}) async {
    if (scope == 'history') {
      historyCompetitionsCalls += 1;
    } else {
      activeCompetitionsCalls += 1;
    }
    return const <String, dynamic>{'competitions': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionProgressV2() async {
    competitionProgressCalls += 1;
    return const <String, dynamic>{'items': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> competitionAchievementsSummaryV2() async {
    achievementsCalls += 1;
    return const <String, dynamic>{'summary': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> endDayReadiness() async {
    readinessCalls += 1;
    return readiness;
  }
}

Widget _wrap(Widget child, DeliveryApi api) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(
      (ref) => _FakeAuthController(ref, const AuthState(token: 'test-token')),
    ),
    deliveryApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.dark(),
    home: child,
  ),
);

void main() {
  testWidgets('delivery dashboard shows end-day readiness warning', (
    tester,
  ) async {
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
    expect(find.textContaining('You cannot close the day yet'), findsOneWidget);
    expect(find.textContaining('App due:'), findsWidgets);
    expect(find.textContaining('Unresolved differences:'), findsWidgets);

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNull);
    expect(api.readinessCalls, greaterThanOrEqualTo(1));
  });
}
