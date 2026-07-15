import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/delivery_api.dart';
import '../models/grouped_delivery_job.dart';
import 'delivery_controller.dart' show deliveryApiProvider;

/// State for the grouped multi-store delivery job screen (delivery closure §3).
class GroupedDeliveryState {
  final bool loading;
  final bool saving;
  final bool historyLoading;
  final GroupedDeliveryJob? job;
  final List<GroupedDeliveryAssignmentHistory> history;
  final String? error;

  const GroupedDeliveryState({
    this.loading = false,
    this.saving = false,
    this.historyLoading = false,
    this.job,
    this.history = const [],
    this.error,
  });

  bool get hasActiveJob => job != null && !job!.isTerminal;

  GroupedDeliveryState copyWith({
    bool? loading,
    bool? saving,
    bool? historyLoading,
    GroupedDeliveryJob? job,
    bool clearJob = false,
    List<GroupedDeliveryAssignmentHistory>? history,
    String? error,
    bool clearError = false,
  }) {
    return GroupedDeliveryState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      historyLoading: historyLoading ?? this.historyLoading,
      job: clearJob ? null : (job ?? this.job),
      history: history ?? this.history,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the authoritative grouped-job contract in the Delivery app:
/// bootstrap/resync, lifecycle mutations, optimistic updates with rollback, and
/// stale-version (409) authoritative refresh. A completed job leaves `job` null
/// (server `current` returns null) so it disappears from Current.
class GroupedDeliveryController extends StateNotifier<GroupedDeliveryState> {
  final DeliveryApi _api;
  Future<void>? _bootstrapInFlight;

  GroupedDeliveryController(this._api) : super(const GroupedDeliveryState());

  bool _isStaleVersion(Object e) =>
      e is DioException &&
      (e.response?.statusCode == 409) &&
      ('${e.response?.data}'.contains('STALE_JOB_VERSION'));

  String _mapError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return '${data['message']}';
      final code = e.response?.statusCode;
      if (code == 409) return 'تعذّر تنفيذ الإجراء في الحالة الحالية.';
      return 'تعذّر الاتصال بالخادم.';
    }
    return 'حدث خطأ غير متوقع.';
  }

  /// Load the current active grouped job (bootstrap / resume / reconnect /
  /// notification tap). Concurrent calls share one in-flight request (§2:
  /// "prevent duplicate simultaneous bootstrap requests").
  Future<void> bootstrap({bool silent = false}) {
    final existing = _bootstrapInFlight;
    if (existing != null) return existing;
    final future = _bootstrap(silent: silent).whenComplete(() {
      _bootstrapInFlight = null;
    });
    _bootstrapInFlight = future;
    return future;
  }

  Future<void> _bootstrap({required bool silent}) async {
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final raw = await _api.currentGroupedJob();
      if (raw == null) {
        state = state.copyWith(loading: false, clearJob: true);
        return;
      }
      // The `current` row is a summary; fetch authoritative details.
      final job = await _fetchDetails(GroupedDeliveryJob.fromMap(raw).deliveryJobId);
      state = state.copyWith(loading: false, job: job, clearError: true);
    } catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    }
  }

  Future<GroupedDeliveryJob> _fetchDetails(int deliveryJobId) async {
    final map = await _api.groupedJobDetails(deliveryJobId);
    return GroupedDeliveryJob.fromMap(map);
  }

  /// Re-fetch the authoritative job state (used after any mutation / on 409).
  Future<void> refresh() async {
    final id = state.job?.deliveryJobId;
    if (id == null) {
      await bootstrap(silent: true);
      return;
    }
    try {
      final job = await _fetchDetails(id);
      // A terminal job leaves Current (mirrors the server `current` contract).
      state = job.isTerminal
          ? state.copyWith(clearJob: true, clearError: true)
          : state.copyWith(job: job, clearError: true);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        state = state.copyWith(clearJob: true);
      } else {
        state = state.copyWith(error: _mapError(e));
      }
    }
  }

  Future<void> loadHistory() async {
    state = state.copyWith(historyLoading: true, clearError: true);
    try {
      final rows = await _api.groupedJobHistory();
      state = state.copyWith(
        historyLoading: false,
        history: rows
            .map((e) => GroupedDeliveryAssignmentHistory.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(historyLoading: false, error: _mapError(e));
    }
  }

  /// Runs a lifecycle mutation with a guard against duplicate taps, an optional
  /// optimistic patch, stale-version refresh, and an authoritative re-fetch.
  Future<void> _mutate(
    Future<Map<String, dynamic>> Function(int id, int version) call, {
    GroupedDeliveryJob? optimistic,
  }) async {
    final job = state.job;
    if (job == null || state.saving) return; // duplicate-tap / no-op guard
    final previous = job;
    state = state.copyWith(saving: true, clearError: true, job: optimistic ?? job);
    try {
      await call(job.deliveryJobId, job.version);
      await refresh();
      state = state.copyWith(saving: false);
    } catch (e) {
      if (_isStaleVersion(e)) {
        await refresh(); // adopt the newer authoritative state
        state = state.copyWith(saving: false);
        return;
      }
      // Roll back the optimistic patch.
      state = state.copyWith(saving: false, job: previous, error: _mapError(e));
    }
  }

  Future<void> acknowledge() =>
      _mutate((id, v) => _api.acknowledgeJob(id, expectedVersion: v));

  Future<void> headingToPickups() =>
      _mutate((id, v) => _api.headingToPickups(id, expectedVersion: v));

  Future<void> arrivedAtStore(int stopId) => _mutate(
        (id, v) => _api.stopArrived(id, stopId, expectedVersion: v),
        optimistic: state.job?.withStopStatus(stopId, 'COURIER_ARRIVED'),
      );

  Future<void> collectStore(int stopId) => _mutate(
        (id, v) => _api.stopCollected(id, stopId, expectedVersion: v),
        optimistic: state.job?.withStopStatus(stopId, 'COLLECTED'),
      );

  Future<void> headingToCustomer() {
    // Client-side guard mirrors the server rule (avoids a pointless 409).
    if (state.job?.canHeadToCustomer != true) return Future.value();
    return _mutate((id, v) => _api.headingToCustomer(id, expectedVersion: v));
  }

  Future<void> markDelivered() {
    if (state.job?.canDeliver != true) return Future.value();
    return _mutate((id, v) => _api.markGroupedDelivered(id, expectedVersion: v));
  }
}

final groupedDeliveryControllerProvider =
    StateNotifierProvider<GroupedDeliveryController, GroupedDeliveryState>((ref) {
  return GroupedDeliveryController(ref.read(deliveryApiProvider));
});
