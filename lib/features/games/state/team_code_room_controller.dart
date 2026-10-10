import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'game_feedback.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/maslaki_realtime_service.dart';
import '../data/games_api.dart';

final teamCodeRoomControllerProvider = StateNotifierProvider.autoDispose
    .family<TeamCodeRoomController, TeamCodeRoomState, int>((ref, roomId) {
      final controller = TeamCodeRoomController(
        roomId: roomId,
        api: ref.read(gamesApiProvider),
        realtime: ref.read(maslakiRealtimeServiceProvider),
      );
      unawaited(controller.start());
      return controller;
    });

class TeamCodeRoomState {
  final Map<String, dynamic>? snapshot;
  final bool loading;
  final bool acting;
  final String? error;

  const TeamCodeRoomState({
    this.snapshot,
    this.loading = true,
    this.acting = false,
    this.error,
  });

  TeamCodeRoomState copyWith({
    Map<String, dynamic>? snapshot,
    bool? loading,
    bool? acting,
    String? error,
    bool clearError = false,
  }) => TeamCodeRoomState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    acting: acting ?? this.acting,
    error: clearError ? null : error ?? this.error,
  );
}

class TeamCodeRoomController extends StateNotifier<TeamCodeRoomState>
    with WidgetsBindingObserver {
  final int roomId;
  final GamesApi api;
  final MaslakiRealtimeClient realtime;
  Timer? _heartbeat;
  Timer? _fallbackRefresh;
  StreamSubscription<MaslakiRealtimeEvent>? _events;
  bool _fetching = false;
  // An event that arrives mid-fetch must not be dropped: it may describe a
  // change the in-flight response predates. Fetch once more afterwards.
  bool _refetchQueued = false;
  bool _disposed = false;
  // Optimistic overlays (local intent not yet confirmed by the server).
  final List<Map<String, dynamic>> _pendingMessages = [];
  Map<String, dynamic>? _pendingVote;
  bool? _pendingReady;

  TeamCodeRoomController({
    required this.roomId,
    required this.api,
    required this.realtime,
  }) : super(const TeamCodeRoomState());

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    final stream = await realtime.subscribeDefaultUserChannel();
    if (_disposed) return;
    _events = stream?.listen((event) {
      if (event.event == 'game_room_updated' &&
          _asInt(event.data['roomId']) == roomId) {
        unawaited(refresh(silent: true));
      }
    });
    // Frequent, tiny beats keep presence stable on flaky mobile networks
    // (the server tolerates several missed beats before showing "away").
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(api.heartbeat(roomId).catchError((_) {}));
    });
    _fallbackRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(refresh(silent: true));
    });
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Coming back to the app: announce presence and resync at once instead of
    // waiting for the next beat or fallback poll. (Not named `state`, which
    // would shadow the notifier's state.)
    if (lifecycle == AppLifecycleState.resumed && !_disposed) {
      unawaited(api.heartbeat(roomId).catchError((_) {}));
      unawaited(refresh(silent: true));
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed) return;
    if (_fetching) {
      _refetchQueued = true;
      return;
    }
    _fetching = true;
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await api.snapshot(roomId);
      if (!_disposed) _applyServerSnapshot(snapshot);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(loading: false, error: _roomLoadMessage(error));
      }
    } finally {
      _fetching = false;
      if (_refetchQueued && !_disposed) {
        _refetchQueued = false;
        unawaited(refresh(silent: true));
      }
    }
  }

  static int _version(Map<String, dynamic>? snapshot) =>
      _asInt((snapshot?['room'] as Map?)?['stateVersion']);

  /// Accepts server state unless it is older than what is already shown (a
  /// slow GET can land after a newer action response), then re-applies any
  /// local intent the server has not confirmed yet.
  void _applyServerSnapshot(Map<String, dynamic> snapshot, {bool acting = false}) {
    if (_version(snapshot) < _version(state.snapshot)) return;
    state = state.copyWith(
      snapshot: _withOptimistic(_stampSnapshot(snapshot)),
      loading: false,
      acting: acting,
      clearError: true,
    );
  }

  Map<String, dynamic> _withOptimistic(Map<String, dynamic> snapshot) {
    var out = snapshot;
    final me = Map<String, dynamic>.from(out['me'] as Map? ?? const {});
    final myMembership = _asInt(me['membershipId']);
    final ready = _pendingReady;
    if (ready != null) {
      final members = (out['members'] as List? ?? const []).map((item) {
        final member = Map<String, dynamic>.from(item as Map);
        if (_asInt(member['membershipId']) != myMembership) return member;
        if (member['isReady'] == ready) _pendingReady = null;
        return {...member, 'isReady': ready};
      }).toList();
      out = {...out, 'members': members};
    }
    final vote = _pendingVote;
    final proposal = out['proposal'] is Map
        ? Map<String, dynamic>.from(out['proposal'] as Map)
        : null;
    if (vote != null) {
      if (proposal == null || _asInt(proposal['id']) != vote['proposalId']) {
        _pendingVote = null;
      } else {
        final votes = (proposal['votes'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .where((item) => _asInt(item['membershipId']) != myMembership)
            .toList();
        out = {
          ...out,
          'proposal': {
            ...proposal,
            'votes': [
              ...votes,
              {'membershipId': myMembership, 'vote': vote['vote']},
            ],
          },
        };
      }
    }
    final serverMessages = (out['messages'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['pending'] != true)
        .toList();
    _pendingMessages.removeWhere(
      (local) => serverMessages.any(
        (message) =>
            _asInt(message['userId']) == _asInt(local['userId']) &&
            message['body'] == local['body'] &&
            DateTime.tryParse('${message['createdAt']}')?.isAfter(
                  (local['_sentAt'] as DateTime).subtract(
                    const Duration(seconds: 30),
                  ),
                ) ==
                true,
      ),
    );
    return {
      ...out,
      'messages': [...serverMessages, ..._pendingMessages],
    };
  }

  String commandId(String action) {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '$action-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  Future<void> setReady(bool ready) async {
    gameFeedback(HapticFeedback.selectionClick);
    _pendingReady = ready;
    _rerender();
    try {
      final snapshot = await api.setReady(roomId, ready);
      _pendingReady = null;
      if (!_disposed) _applyServerSnapshot(snapshot);
    } catch (error) {
      _pendingReady = null;
      if (_disposed) return;
      state = state.copyWith(error: _gameActionMessage(error));
      unawaited(refresh(silent: true));
    }
  }

  void _rerender() {
    final snapshot = state.snapshot;
    if (_disposed || snapshot == null) return;
    state = state.copyWith(snapshot: _withOptimistic(snapshot), clearError: true);
  }
  Future<void> launch() => _run(() => api.start(roomId));
  Future<void> attempt(String code) => _run(
    () => api.attempt(roomId, code: code, commandId: commandId('attempt')),
  );
  Future<void> hint() => _run(() => api.hint(roomId, commandId('solo-hint')));
  Future<void> proposeCode(String code) => _run(
    () => api.propose(
      roomId,
      kind: 'code',
      code: code,
      commandId: commandId('proposal'),
    ),
  );
  Future<void> proposeHint() => _run(
    () => api.propose(roomId, kind: 'hint', commandId: commandId('hint')),
  );
  Future<void> vote(int proposalId, bool approve) async {
    final choice = approve ? 'approve' : 'reject';
    gameFeedback(HapticFeedback.selectionClick);
    _pendingVote = {'proposalId': proposalId, 'vote': choice};
    _rerender();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // A vote is an idempotent upsert, so a retry cannot double count.
        final snapshot = await api.vote(roomId, proposalId, choice);
        if (_pendingVote?['proposalId'] == proposalId) _pendingVote = null;
        if (!_disposed) _applyServerSnapshot(snapshot);
        return;
      } catch (error) {
        if (_disposed) return;
        if (_isTransient(error) && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        if (_pendingVote?['proposalId'] == proposalId) _pendingVote = null;
        state = state.copyWith(error: _gameActionMessage(error));
        unawaited(refresh(silent: true));
        return;
      }
    }
  }
  Future<void> continueSolo() => _run(() => api.continueSolo(roomId));

  Future<void> sendMessage(String text) async {
    final body = text.trim();
    final snapshot = state.snapshot;
    if (body.isEmpty || snapshot == null) return;
    final me = Map<String, dynamic>.from(snapshot['me'] as Map? ?? const {});
    final mine = (snapshot['members'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((m) => _asInt(m['userId']) == _asInt(me['userId']))
        .firstOrNull;
    final local = <String, dynamic>{
      'id': -DateTime.now().microsecondsSinceEpoch,
      'body': body,
      'userId': me['userId'],
      'senderName': mine?['name'] ?? 'أنت',
      'pending': true,
      '_sentAt': DateTime.now(),
    };
    gameFeedback(HapticFeedback.selectionClick);
    _pendingMessages.add(local);
    _rerender();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await api.message(roomId, body);
        // The realtime echo replaces the bubble; refresh in case it is lost.
        unawaited(refresh(silent: true));
        return;
      } catch (error) {
        if (_disposed) return;
        if (_isTransient(error) && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        _pendingMessages.remove(local);
        _rerender();
        state = state.copyWith(error: 'لم تُرسل الرسالة. تحقق من الاتصال وأعد المحاولة.');
        return;
      }
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (state.acting) return;
    gameFeedback(HapticFeedback.lightImpact);
    state = state.copyWith(acting: true, clearError: true);
    try {
      final snapshot = await action();
      if (!_disposed) {
        if (_version(snapshot) >= _version(state.snapshot)) {
          _applyServerSnapshot(snapshot);
        } else {
          state = state.copyWith(acting: false);
        }
      }
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(acting: false, error: _gameActionMessage(error));
        if (_isRoundTimeout(error)) unawaited(refresh(silent: true));
      }
    }
  }

  static int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  Map<String, dynamic> _stampSnapshot(Map<String, dynamic> snapshot) => {
    ...snapshot,
    '_clientReceivedAtMs': DateTime.now().millisecondsSinceEpoch,
  };

  static bool _isTransient(Object error) =>
      error is DioException &&
      (error.response == null || (error.response!.statusCode ?? 0) >= 500);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _fallbackRefresh?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }
}

String _roomLoadMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final code = data is Map ? '${data['message'] ?? data['code'] ?? ''}' : '';
    if (status == 403 || code == 'GAME_ROOM_FORBIDDEN') {
      return 'لقد غادرت هذه الجولة، لذلك لم تعد قابلة للاستعادة.';
    }
    if (status == 404 || code == 'GAME_ROOM_NOT_FOUND') {
      return 'هذه الجولة لم تعد موجودة أو انتهت مدة الاحتفاظ بها.';
    }
  }
  return 'تعذر الاتصال بالغرفة. تحقق من الشبكة ثم حاول مجددًا.';
}

bool _isRoundTimeout(Object error) {
  if (error is! DioException) return false;
  final data = error.response?.data;
  final code = data is Map ? '${data['message'] ?? data['code'] ?? ''}' : '';
  return code == 'GAME_ROUND_TIMED_OUT';
}

String _gameActionMessage(Object error) {
  if (_isRoundTimeout(error)) {
    return 'انتهى وقت الخزنة. جارٍ اعتماد نتيجة الجولة.';
  }
  if (error is DioException) {
    final data = error.response?.data;
    final code = data is Map ? '${data['message'] ?? data['code'] ?? ''}' : '';
    if (code == 'GAME_WAITING_FOR_RECONNECT') {
      return 'التصويت متوقف مؤقتًا حتى يعود عضو الفريق.';
    }
    if (code == 'GAME_PROPOSAL_ALREADY_ACTIVE') {
      return 'يوجد اقتراح قيد التصويت بالفعل.';
    }
  }
  return 'تعذر تنفيذ الأمر. تحقق من الاتصال وحاول مجددًا.';
}
