import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
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

class TeamCodeRoomController extends StateNotifier<TeamCodeRoomState> {
  final int roomId;
  final GamesApi api;
  final MaslakiRealtimeClient realtime;
  Timer? _heartbeat;
  Timer? _fallbackRefresh;
  StreamSubscription<MaslakiRealtimeEvent>? _events;
  bool _fetching = false;
  bool _disposed = false;

  TeamCodeRoomController({
    required this.roomId,
    required this.api,
    required this.realtime,
  }) : super(const TeamCodeRoomState());

  Future<void> start() async {
    await refresh();
    final stream = await realtime.subscribeDefaultUserChannel();
    if (_disposed) return;
    _events = stream?.listen((event) {
      if (event.event == 'game_room_updated' &&
          _asInt(event.data['roomId']) == roomId) {
        unawaited(refresh(silent: true));
      }
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(api.heartbeat(roomId).catchError((_) {}));
    });
    _fallbackRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(refresh(silent: true));
    });
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _fetching) return;
    _fetching = true;
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await api.snapshot(roomId);
      if (!_disposed) {
        state = state.copyWith(
          snapshot: _stampSnapshot(snapshot),
          loading: false,
          acting: false,
          clearError: true,
        );
      }
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          loading: false,
          acting: false,
          error: _roomLoadMessage(error),
        );
      }
    } finally {
      _fetching = false;
    }
  }

  String commandId(String action) {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '$action-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  Future<void> setReady(bool ready) => _run(() => api.setReady(roomId, ready));
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
  Future<void> vote(int proposalId, bool approve) =>
      _run(() => api.vote(roomId, proposalId, approve ? 'approve' : 'reject'));
  Future<void> continueSolo() => _run(() => api.continueSolo(roomId));

  Future<void> sendMessage(String text) async {
    await api.message(roomId, text);
    await refresh(silent: true);
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (state.acting) return;
    state = state.copyWith(acting: true, clearError: true);
    try {
      final snapshot = await action();
      if (!_disposed) {
        state = state.copyWith(
          snapshot: _stampSnapshot(snapshot),
          acting: false,
          loading: false,
          clearError: true,
        );
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

  @override
  void dispose() {
    _disposed = true;
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
