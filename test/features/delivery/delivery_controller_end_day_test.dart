import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi({required this.readiness, required this.endDayResponse})
    : super(Dio());

  final Map<String, dynamic> readiness;
  final Map<String, dynamic> endDayResponse;

  int readinessCalls = 0;
  int endDayCalls = 0;
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

  @override
  Future<Map<String, dynamic>> endDay({String? date}) async {
    endDayCalls += 1;
    return endDayResponse;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delivery end day is blocked while an open settlement remains',
    () async {
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
        endDayResponse: const <String, dynamic>{},
      );
      final container = ProviderContainer(
        overrides: [deliveryApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(deliveryControllerProvider.notifier).endDay();

      final state = container.read(deliveryControllerProvider);
      expect(api.readinessCalls, 1);
      expect(api.endDayCalls, 0);
      expect(state.saving, false);
      expect(state.error, isNotNull);
      expect(state.error, contains('Cannot close the day'));
      expect(state.endDayReadiness['canEndDay'], false);
    },
  );

  test(
    'delivery end day is blocked while difference review remains open',
    () async {
      final api = _FakeDeliveryApi(
        readiness: const {
          'canEndDay': false,
          'outstandingAmount': 1550,
          'totalAppDue': 1500,
          'totalDifferenceDue': 50,
          'blockingReasonEn':
              'There are unresolved cash settlements or an open difference review.',
          'openSettlements': [
            {
              'id': 9,
              'appDueFromDelivery': 1500,
              'differenceAmount': 50,
              'settlementStatus': 'difference_review',
              'status': 'received',
            },
          ],
        },
        endDayResponse: const <String, dynamic>{},
      );
      final container = ProviderContainer(
        overrides: [deliveryApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(deliveryControllerProvider.notifier).endDay();

      final state = container.read(deliveryControllerProvider);
      expect(api.readinessCalls, 1);
      expect(api.endDayCalls, 0);
      expect(state.error, contains('Cannot close the day'));
      expect(state.error, contains('difference review'));
      expect(state.endDayReadiness['totalDifferenceDue'], 50);
    },
  );

  test('delivery end day submits once readiness is clear', () async {
    final api = _FakeDeliveryApi(
      readiness: const {
        'canEndDay': true,
        'outstandingAmount': 0,
        'openSettlements': <dynamic>[],
      },
      endDayResponse: const {
        'archiveDate': '2026-07-05',
        'ordersCount': 3,
        'totalAmount': 11250,
        'storeNetReceivedAmount': 8750,
        'appDueFromDelivery': 1500,
      },
    );
    final container = ProviderContainer(
      overrides: [deliveryApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(deliveryControllerProvider.notifier).endDay();

    final state = container.read(deliveryControllerProvider);
    expect(api.readinessCalls, 2);
    expect(api.endDayCalls, 1);
    expect(api.ordersCalls, 1);
    expect(api.analyticsCalls, 1);
    expect(api.dashboardCalls, 1);
    expect(api.reportsCalls, 1);
    expect(api.requestsCalls, 1);
    expect(api.activeCompetitionsCalls, 1);
    expect(api.historyCompetitionsCalls, 1);
    expect(api.competitionProgressCalls, 1);
    expect(api.achievementsCalls, 1);
    expect(state.saving, false);
    expect(state.error, isNull);
    expect(state.endDayReadiness['canEndDay'], true);
    expect(state.lastArchiveMessage, isNotNull);
  });
}
