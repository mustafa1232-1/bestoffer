import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/models/grouped_delivery_job.dart';
import 'package:maslaki/features/delivery/state/grouped_delivery_controller.dart';

/// In-memory fake backend for the grouped-job contract. Holds one job whose
/// details endpoint reflects mutations, so the controller's refresh() observes
/// authoritative state exactly like production.
class FakeDeliveryApi extends DeliveryApi {
  FakeDeliveryApi() : super(Dio());

  int version = 1;
  String lifecycle = 'ASSIGNED';
  final Map<int, String> stopStatus = {101: 'READY', 102: 'READY'};
  bool throwStaleOnce = false;

  Map<String, dynamic> _details() => {
    'deliveryJobId': 7,
    'assignmentId': 55,
    'orderGroupId': 3,
    'lifecycleStatus': lifecycle,
    'assignmentStatus': 'ASSIGNED',
    'numberOfStores': 2,
    'paymentMethod': 'cash',
    'courierEarning': 4000,
    'version': version,
    'pickupStops': [
      {
        'stopId': 101,
        'childOrderId': 1001,
        'storeId': 11,
        'storeName': 'متجر ١',
        'sequence': 1,
        'preparationStatus': 'READY',
        'pickupStatus': stopStatus[101],
      },
      {
        'stopId': 102,
        'childOrderId': 1002,
        'storeId': 12,
        'storeName': 'متجر ٢',
        'sequence': 2,
        'preparationStatus': 'READY',
        'pickupStatus': stopStatus[102],
      },
    ],
  };

  bool get _terminal =>
      lifecycle == 'DELIVERED' ||
      lifecycle == 'CANCELLED' ||
      lifecycle == 'FAILED';

  DioException _staleVersion() => DioException(
    requestOptions: RequestOptions(path: '/x'),
    response: Response(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: 409,
      data: {'code': 'STALE_JOB_VERSION'},
    ),
  );

  DioException _conflict(String code) => DioException(
    requestOptions: RequestOptions(path: '/x'),
    response: Response(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: 409,
      data: {'code': code, 'message': code},
    ),
  );

  @override
  Future<Map<String, dynamic>?> currentGroupedJob({
    bool skipTerminalSessionInvalidation = false,
  }) async => _terminal ? null : {'delivery_job_id': 7};

  @override
  Future<Map<String, dynamic>> groupedJobDetails(int deliveryJobId) async =>
      _details();

  @override
  Future<List<dynamic>> groupedJobHistory({int limit = 50}) async =>
      _terminal ? [_details()] : const [];

  @override
  Future<Map<String, dynamic>> acknowledgeJob(
    int id, {
    int? expectedVersion,
  }) async {
    lifecycle = 'ACKNOWLEDGED';
    version++;
    return {'lifecycleStatus': lifecycle};
  }

  @override
  Future<Map<String, dynamic>> headingToPickups(
    int id, {
    int? expectedVersion,
  }) async {
    lifecycle = 'HEADING_TO_PICKUPS';
    version++;
    return {'lifecycleStatus': lifecycle};
  }

  @override
  Future<Map<String, dynamic>> stopArrived(
    int id,
    int stopId, {
    int? expectedVersion,
  }) async {
    stopStatus[stopId] = 'COURIER_ARRIVED';
    version++;
    return {'pickupStatus': 'COURIER_ARRIVED'};
  }

  @override
  Future<Map<String, dynamic>> stopCollected(
    int id,
    int stopId, {
    int? expectedVersion,
  }) async {
    if (throwStaleOnce) {
      throwStaleOnce = false;
      version++; // server advanced under us
      throw _staleVersion();
    }
    stopStatus[stopId] = 'COLLECTED';
    version++;
    return {'pickupStatus': 'COLLECTED'};
  }

  @override
  Future<Map<String, dynamic>> headingToCustomer(
    int id, {
    int? expectedVersion,
  }) async {
    final allCollected = stopStatus.values.every((s) => s == 'COLLECTED');
    if (!allCollected) throw _conflict('PICKUPS_INCOMPLETE');
    lifecycle = 'HEADING_TO_CUSTOMER';
    version++;
    return {'lifecycleStatus': lifecycle};
  }

  @override
  Future<Map<String, dynamic>> markGroupedDelivered(
    int id, {
    int? expectedVersion,
  }) async {
    lifecycle = 'DELIVERED';
    version++;
    return {'lifecycleStatus': lifecycle};
  }
}

void main() {
  group('GroupedDeliveryJob model', () {
    GroupedDeliveryJob build(
      String s1,
      String s2, {
      String lifecycle = 'ASSIGNED',
    }) {
      return GroupedDeliveryJob.fromMap({
        'deliveryJobId': 7,
        'orderGroupId': 3,
        'lifecycleStatus': lifecycle,
        'assignmentStatus': 'ASSIGNED',
        'assignmentId': 55,
        'version': 1,
        'pickupStops': [
          {
            'stopId': 101,
            'childOrderId': 1,
            'storeId': 11,
            'storeName': 'a',
            'sequence': 1,
            'pickupStatus': s1,
            'preparationStatus': 'READY',
          },
          {
            'stopId': 102,
            'childOrderId': 2,
            'storeId': 12,
            'storeName': 'b',
            'sequence': 2,
            'pickupStatus': s2,
            'preparationStatus': 'READY',
          },
        ],
      });
    }

    test('parses snake_case and camelCase equally', () {
      final job = GroupedDeliveryJob.fromMap({
        'delivery_job_id': 9,
        'order_group_id': 2,
        'lifecycle_status': 'ASSIGNED',
        'assignment_status': 'ASSIGNED',
        'assignment_id': 5,
        'pickupStops': [
          {
            'id': 1,
            'child_order_id': 3,
            'store_id': 4,
            'store_name': 's',
            'sequence_number': 1,
            'pickup_status': 'READY',
          },
        ],
      });
      expect(job.deliveryJobId, 9);
      expect(job.assignmentId, 5);
      expect(job.pickupStops.single.storeId, 4);
      expect(job.storesLabel, 'طلب من 1 متاجر');
    });

    test('collecting store 1 leaves store 2 pending', () {
      final job = build('COLLECTED', 'READY');
      expect(job.collectedCount, 1);
      expect(job.allCollected, isFalse);
      expect(job.canHeadToCustomer, isFalse);
    });

    test('heading to customer only when all active stops collected', () {
      expect(build('COLLECTED', 'COLLECTED').canHeadToCustomer, isTrue);
      expect(build('COLLECTED', 'READY').canHeadToCustomer, isFalse);
    });

    test('cancelled stop is excluded from the active set', () {
      final job = build('COLLECTED', 'CANCELLED');
      expect(job.numberOfStores, 1);
      expect(job.allCollected, isTrue); // only the one active stop matters
    });

    test('terminal lifecycle detection', () {
      expect(
        build('COLLECTED', 'COLLECTED', lifecycle: 'DELIVERED').isTerminal,
        isTrue,
      );
      expect(build('READY', 'READY').isTerminal, isFalse);
    });
  });

  group('GroupedDeliveryController lifecycle', () {
    test('bootstrap loads the current job', () async {
      final c = GroupedDeliveryController(FakeDeliveryApi());
      await c.bootstrap();
      expect(c.state.job, isNotNull);
      expect(c.state.job!.numberOfStores, 2);
    });

    test(
      'per-stop collection: stop 1 collected, stop 2 pending, gating holds',
      () async {
        final api = FakeDeliveryApi();
        final c = GroupedDeliveryController(api);
        await c.bootstrap();

        await c.collectStore(101);
        expect(c.state.job!.collectedCount, 1);
        expect(c.state.job!.allCollected, isFalse);

        // Blocked: not all collected → no-op, job stays pre-customer.
        await c.headingToCustomer();
        expect(
          c.state.job!.lifecycle,
          isNot(GroupedJobLifecycle.headingToCustomer),
        );

        await c.collectStore(102);
        expect(c.state.job!.allCollected, isTrue);

        await c.headingToCustomer();
        expect(c.state.job!.lifecycle, GroupedJobLifecycle.headingToCustomer);
      },
    );

    test(
      'delivered clears the current job (does not reopen completed work)',
      () async {
        final api = FakeDeliveryApi();
        final c = GroupedDeliveryController(api);
        await c.bootstrap();
        await c.collectStore(101);
        await c.collectStore(102);
        await c.headingToCustomer();
        await c.markDelivered();
        expect(c.state.job, isNull, reason: 'completed job leaves Current');

        await c.bootstrap();
        expect(
          c.state.job,
          isNull,
          reason: 'restart does not reopen a delivered job',
        );
      },
    );

    test(
      'delivered forces delivery orders and idle presence resync once',
      () async {
        final api = FakeDeliveryApi();
        var terminalResyncs = 0;
        final c = GroupedDeliveryController(
          api,
          onTerminalCompletion: () async {
            terminalResyncs++;
          },
        );
        await c.bootstrap();

        await c.collectStore(101);
        await c.collectStore(102);
        await c.headingToCustomer();
        expect(terminalResyncs, 0);

        await c.markDelivered();
        expect(c.state.job, isNull);
        expect(
          terminalResyncs,
          1,
          reason:
              'completion must immediately refresh current orders and force idle presence sync',
        );
      },
    );

    test(
      'terminal resync failure is nonblocking and logged once safely',
      () async {
        final api = FakeDeliveryApi();
        final logs = <String>[];
        var terminalResyncs = 0;
        final c = GroupedDeliveryController(
          api,
          onTerminalCompletion: () async {
            terminalResyncs++;
            throw DioException(
              requestOptions: RequestOptions(path: '/api/delivery/current'),
              type: DioExceptionType.connectionError,
            );
          },
          terminalResyncLogger: logs.add,
        );
        await c.bootstrap();

        await c.collectStore(101);
        await c.collectStore(102);
        await c.headingToCustomer();
        await c.markDelivered();
        await Future<void>.delayed(Duration.zero);

        expect(c.state.job, isNull);
        expect(c.state.saving, isFalse);
        expect(c.state.error, isNull);
        expect(terminalResyncs, 1);
        expect(logs, hasLength(1));
        expect(logs.single, contains('event=delivery_terminal_resync_failed'));
        expect(logs.single, contains('surface=delivery'));
        expect(logs.single, contains('deliveryJobId=7'));
        expect(logs.single, contains('APP_SHA='));
        expect(logs.single, contains('category=network'));
        expect(logs.single, isNot(contains('DioException')));
        expect(logs.single, isNot(contains('RequestOptions')));
        expect(logs.single, isNot(contains('/api/delivery/current')));
      },
    );

    test(
      'stale version (409) triggers an authoritative refresh, no crash',
      () async {
        final api = FakeDeliveryApi()..throwStaleOnce = true;
        final c = GroupedDeliveryController(api);
        await c.bootstrap();
        await c.collectStore(
          101,
        ); // server throws stale once → controller refreshes
        expect(c.state.error, isNull);
        expect(c.state.saving, isFalse);
        expect(c.state.job, isNotNull);
      },
    );

    test('duplicate tap while saving is ignored', () async {
      final api = FakeDeliveryApi();
      final c = GroupedDeliveryController(api);
      await c.bootstrap();
      final f1 = c.collectStore(101);
      final f2 = c.collectStore(101); // should be ignored (saving guard)
      await Future.wait([f1, f2]);
      expect(c.state.job!.collectedCount, 1);
    });

    test(
      'bootstrap failure with a cached job → cachedOffline, mutations blocked',
      () async {
        final api = TogglingDeliveryApi();
        final c = GroupedDeliveryController(api);
        await c.bootstrap(); // ok → job present
        expect(c.state.job, isNotNull);

        api.fail = true;
        await c.resync(); // fails → keep cached job, mark offline
        expect(c.state.cachedOffline, isTrue);
        expect(c.state.isErrorWithoutJob, isFalse);
        expect(c.state.mutationsBlocked, isTrue);

        // A mutation while offline does not mutate (it tries to re-sync first).
        await c.collectStore(101);
        expect(c.state.job!.collectedCount, 0);

        // Recover → offline flag cleared, mutations allowed again.
        api.fail = false;
        await c.resync();
        expect(c.state.cachedOffline, isFalse);
      },
    );

    test(
      'reset() invalidates in-flight results (no cross-user leak)',
      () async {
        final api = SlowDeliveryApi();
        final c = GroupedDeliveryController(api);
        final f = c.bootstrap(); // starts slow request
        c.reset(); // logout / account switch before it resolves
        api.complete();
        await f;
        expect(c.state.job, isNull, reason: 'stale result must not leak in');
      },
    );
  });
}

/// Fake whose currentGroupedJob can be toggled to fail.
class TogglingDeliveryApi extends FakeDeliveryApi {
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> currentGroupedJob({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
    }
    return super.currentGroupedJob();
  }

  @override
  Future<Map<String, dynamic>> groupedJobDetails(int id) async {
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
    }
    return super.groupedJobDetails(id);
  }
}

/// Fake with a manually-completed currentGroupedJob to test the generation guard.
class SlowDeliveryApi extends FakeDeliveryApi {
  final _c = Completer<void>();
  void complete() => _c.complete();
  @override
  Future<Map<String, dynamic>?> currentGroupedJob({
    bool skipTerminalSessionInvalidation = false,
  }) async {
    await _c.future;
    return super.currentGroupedJob();
  }
}
