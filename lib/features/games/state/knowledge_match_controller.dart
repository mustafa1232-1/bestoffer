import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'game_feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/realtime/maslaki_realtime_service.dart';
import '../data/games_api.dart';

final knowledgeRealtimeProvider = Provider<MaslakiRealtimeClient?>(
  (ref) => ref.read(maslakiRealtimeServiceProvider),
);

enum KnowledgeSubmission {
  idle,
  selected,
  submitting,
  confirmed,
  reconciling,
  closed,
  failed,
}

Map<String, dynamic> knowledgeMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
int knowledgeInt(dynamic value) => int.tryParse('$value') ?? 0;

String knowledgeErrorCode(Object error) {
  if (error is! DioException) return 'UNAVAILABLE';
  final data = knowledgeMap(error.response?.data);
  return '${data['code'] ?? knowledgeMap(data['error'])['code'] ?? error.response?.statusCode ?? error.type.name}';
}

String knowledgeErrorText(Object error) => switch (knowledgeErrorCode(error)) {
  '401' ||
  'UNAUTHORIZED' ||
  'INVALID_TOKEN' ||
  'TOKEN_EXPIRED' => 'انتهت الجلسة. سجّل الدخول للعودة إلى المباراة.',
  'GAME_UPDATE_REQUIRED' || '426' => 'تحتاج اللعبة إلى آخر تحديث من التطبيق.',
  'QUESTION_NOT_OPEN' => 'لم يبدأ وقت السؤال بعد.',
  'QUESTION_EXPIRED' ||
  'ROUND_CLOSED' ||
  'STALE_QUESTION' => 'انتهى هذا السؤال. نحدّث الجولة الآن.',
  'ANSWER_ALREADY_RECORDED' => 'لديك إجابة مسجلة. نستعيدها الآن.',
  'IDEMPOTENCY_CONFLICT' =>
    'المحاولة مسجلة باختيار آخر. نتحقق من الإجابة المحفوظة.',
  'DISTRICT_INVALID' => 'هذه المنطقة غير متاحة الآن. اختر منطقة متصلة بفريقك.',
  'MATCH_NOT_FOUND_OR_FORBIDDEN' ||
  '403' ||
  '404' => 'المباراة غير متاحة لهذا الحساب.',
  '429' ||
  'RATE_LIMITED' => 'طلبات كثيرة خلال وقت قصير. انتظر قليلًا ثم أعد المحاولة.',
  _ => 'تعذر الاتصال باللعبة. سنحافظ على اختيارك أثناء التحقق.',
};

abstract class KnowledgeAttemptStore {
  Future<Map<String, dynamic>?> read(String scope);
  Future<void> write(String scope, Map<String, dynamic>? value);
}

class LocalKnowledgeAttemptStore implements KnowledgeAttemptStore {
  @override
  Future<Map<String, dynamic>?> read(String scope) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'knowledge.attempt.$scope',
    );
    if (raw == null) return null;
    try {
      return knowledgeMap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String scope, Map<String, dynamic>? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('knowledge.attempt.$scope');
    } else {
      await prefs.setString('knowledge.attempt.$scope', jsonEncode(value));
    }
  }
}

// One in-flight snapshot and one immutable answer attempt. Realtime invalidates;
// the database snapshot remains authoritative after event loss or process death.
class KnowledgeMatchController extends ChangeNotifier {
  KnowledgeMatchController({
    required this.api,
    required this.matchId,
    this.realtime,
    KnowledgeAttemptStore? store,
    this.polling = true,
  }) : store = store ?? LocalKnowledgeAttemptStore();
  final GamesApi api;
  final int matchId;
  final MaslakiRealtimeClient? realtime;
  final KnowledgeAttemptStore store;
  final bool polling;
  Map<String, dynamic> snapshot = {};
  KnowledgeSubmission submission = KnowledgeSubmission.idle;
  int? selectedAnswer;
  String? selectedDistrict;
  String? message;
  bool offline = false;
  bool loading = true;
  Map<String, dynamic>? _attempt;
  StreamSubscription<MaslakiRealtimeEvent>? _events;
  Timer? _fallback;
  Timer? _boundary;
  final _seenEvents = <String>{};
  final _clock = Stopwatch();
  // Measures, on this device, how long the open question has been visible.
  final _questionWatch = Stopwatch();
  int? _questionWatchRound;
  DateTime _serverTime = DateTime.now().toUtc();
  DateTime? _lastEvent;
  bool _disposed = false,
      _fetching = false,
      _refreshAgain = false,
      _binding = false,
      _sending = false,
      _active = true;
  bool _sessionExpired = false;
  int _failures = 0;
  String get _scope => '${snapshot['myUserId'] ?? 0}.$matchId';
  int get roundId => knowledgeInt(knowledgeMap(snapshot['round'])['id']);
  int get version => knowledgeInt(snapshot['stateVersion']);
  Map<String, dynamic> get pendingAttempt => Map.unmodifiable(_attempt ?? {});
  DateTime get serverNow => _serverTime.add(_clock.elapsed);
  DateTime? get deadline =>
      DateTime.tryParse('${knowledgeMap(snapshot['round'])['deadlineAt']}');
  bool get canSelect =>
      !_sessionExpired &&
      snapshot['phase'] == 'question_open' &&
      deadline != null &&
      serverNow.isBefore(deadline!) &&
      ![
        KnowledgeSubmission.submitting,
        KnowledgeSubmission.confirmed,
        KnowledgeSubmission.reconciling,
        KnowledgeSubmission.closed,
      ].contains(submission);
  bool get canSubmit =>
      canSelect &&
      selectedAnswer != null &&
      selectedDistrict != null &&
      _attempt == null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    unawaited(_bind());
    await refresh();
    if (_disposed || snapshot.isEmpty) return;
    try {
      final saved = await store.read(_scope);
      if (_disposed || saved == null || snapshot['answered'] == true) return;
      _attempt = saved;
      if (knowledgeInt(saved['roundId']) == roundId) {
        selectedAnswer = knowledgeInt(saved['answerIndex']);
        selectedDistrict = '${saved['districtId']}';
        submission = KnowledgeSubmission.reconciling;
        _notify();
      }
      await reconcile();
    } catch (_) {
      /* A storage failure must not invent a confirmed answer. */
    }
  }

  Future<void> _bind() async {
    if (_binding ||
        _events != null ||
        realtime == null ||
        _disposed ||
        !_active) {
      return;
    }
    _binding = true;
    try {
      final stream = await realtime!.subscribeDefaultUserChannel();
      if (_disposed || !_active) return;
      _events = stream?.listen(
        (event) {
          if (!event.event.startsWith('knowledge_') ||
              knowledgeInt(event.data['matchId']) != matchId) {
            return;
          }
          final key =
              '${event.event}:${event.data['eventId'] ?? event.eventId}';
          if (event.data['eventId'] != null && !_seenEvents.add(key)) return;
          if (_seenEvents.length > 256) _seenEvents.remove(_seenEvents.first);
          if (knowledgeInt(event.data['stateVersion']) > 0 &&
              knowledgeInt(event.data['stateVersion']) < version) {
            return;
          }
          _lastEvent = DateTime.now();
          unawaited(refresh());
        },
        onError: (Object _) {
          offline = true;
          _notify();
        },
        onDone: () {
          _events = null;
        },
      );
    } catch (_) {
      /* Bounded HTTP fallback remains available without realtime. */
    } finally {
      _binding = false;
    }
  }

  void _schedule() {
    _fallback?.cancel();
    _boundary?.cancel();
    if (!polling ||
        _disposed ||
        !_active ||
        _sessionExpired ||
        snapshot['phase'] == 'finished') {
      return;
    }
    final recent =
        _lastEvent != null &&
        DateTime.now().difference(_lastEvent!).inSeconds < 12;
    final seconds = _failures > 0
        ? min(20, 3 * (1 << min(_failures - 1, 3)))
        : recent
        ? 10
        : 3;
    _fallback = Timer(
      Duration(milliseconds: seconds * 1000 + Random().nextInt(600)),
      () {
        unawaited(_bind());
        unawaited(refresh());
      },
    );
    final round = knowledgeMap(snapshot['round']);
    final phase = snapshot['phase'];
    final key = phase == 'countdown'
        ? 'startsAt'
        : phase == 'round_result'
        ? 'nextAt'
        : 'deadlineAt';
    var time = DateTime.tryParse('${round[key]}');
    // After the deadline the server waits out the in-flight answer grace
    // (1.5s) before scoring; look again right after it.
    if (time != null && phase == 'resolving') {
      time = time.add(const Duration(milliseconds: 1700));
    }
    if (time != null) {
      final wait = time.difference(serverNow);
      // Already past the boundary (clock skew or a slow response): retry
      // quickly instead of waiting for the multi-second fallback.
      _boundary = Timer(
        wait.isNegative
            ? const Duration(milliseconds: 200)
            : wait + const Duration(milliseconds: 60),
        () => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed || !_active) return;
    if (_fetching) {
      _refreshAgain = true;
      return;
    }
    _fetching = true;
    try {
      final value = await api.knowledgeMatch(matchId);
      if (_disposed) return;
      applySnapshot(value);
      offline = false;
      _sessionExpired = false;
      _failures = 0;
    } catch (error) {
      if (_disposed) return;
      offline = true;
      _failures++;
      message = knowledgeErrorText(error);
      _sessionExpired =
          error is DioException && error.response?.statusCode == 401;
    } finally {
      _fetching = false;
      loading = false;
      _notify();
      _schedule();
      if (_refreshAgain && !_disposed) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }

  @visibleForTesting
  void applySnapshot(Map<String, dynamic> value) {
    final incomingVersion = knowledgeInt(value['stateVersion']);
    if (incomingVersion < version) return;
    final incomingTime = DateTime.tryParse('${value['serverTime']}');
    final previousTime = DateTime.tryParse('${snapshot['serverTime']}');
    if (incomingVersion == version &&
        incomingTime != null &&
        previousTime != null &&
        incomingTime.isBefore(previousTime)) {
      return;
    }
    final nextRound = knowledgeInt(knowledgeMap(value['round'])['id']);
    if (nextRound != roundId) {
      selectedAnswer = null;
      selectedDistrict = null;
      submission = KnowledgeSubmission.idle;
      message = null;
      if (!_sending) {
        _attempt = null;
        unawaited(_persist(null));
      }
    }
    // A snapshot begun before the HTTP commit can have the same state version.
    // It must not erase our durable receipt for this exact round.
    if (nextRound == roundId &&
        snapshot['answered'] == true &&
        value['answered'] != true) {
      value = {...value, 'answered': true, 'ownAnswer': snapshot['ownAnswer']};
    }
    snapshot = value;
    _serverTime = incomingTime ?? DateTime.now().toUtc();
    _clock
      ..reset()
      ..start();
    final visibleQuestion = knowledgeMap(value['question']);
    if (value['phase'] == 'question_open' &&
        '${visibleQuestion['text'] ?? ''}'.isNotEmpty &&
        _questionWatchRound != roundId) {
      _questionWatchRound = roundId;
      _questionWatch
        ..reset()
        ..start();
    }
    final own = knowledgeMap(value['ownAnswer']);
    if (value['answered'] == true) {
      submission = KnowledgeSubmission.confirmed;
      selectedAnswer = own['answerIndex'] == null
          ? selectedAnswer
          : knowledgeInt(own['answerIndex']);
      selectedDistrict = own['districtId']?.toString() ?? selectedDistrict;
      _attempt = null;
      message = null;
      unawaited(_persist(null));
    } else if ([
          'round_result',
          'finished',
          'resolving',
        ].contains(value['phase']) &&
        submission != KnowledgeSubmission.confirmed &&
        !_sending) {
      submission = KnowledgeSubmission.closed;
    } else if (value['phase'] == 'question_open' &&
        submission == KnowledgeSubmission.closed &&
        _attempt == null) {
      // A premature send may be rejected while the shared countdown finishes.
      submission = selectedAnswer == null
          ? KnowledgeSubmission.idle
          : KnowledgeSubmission.selected;
      message = null;
    }
    if (selectedDistrict == null &&
        (knowledgeMap(value['match'])['availableDistricts'] as List? ?? [])
            .isEmpty) {
      selectedDistrict = 'none';
    }
  }

  void selectAnswer(int value) {
    if (canSelect) {
      gameFeedback(HapticFeedback.selectionClick);
      selectedAnswer = value;
      submission = KnowledgeSubmission.selected;
      _notify();
    }
  }

  void selectDistrict(String value) {
    if (canSelect) {
      gameFeedback(HapticFeedback.selectionClick);
      selectedDistrict = value;
      submission = KnowledgeSubmission.selected;
      _notify();
    }
  }

  Future<void> _persist(Map<String, dynamic>? attempt) async {
    try {
      await store.write(_scope, attempt);
    } catch (_) {
      /* Snapshot recovery still works if local storage is unavailable. */
    }
  }

  Future<void> submit() async {
    if (!canSubmit || _sending) return;
    final random = Random.secure();
    final key = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    gameFeedback(HapticFeedback.mediumImpact);
    _attempt = {
      'roundId': roundId,
      'questionId': knowledgeInt(knowledgeMap(snapshot['question'])['id']),
      'answerIndex': selectedAnswer,
      'districtId': selectedDistrict,
      'idempotencyKey': key,
      if (_questionWatchRound == roundId)
        'clientElapsedMs': _questionWatch.elapsedMilliseconds,
    };
    await _sendAttempt();
  }

  Future<void> _sendAttempt() async {
    if (_sending || _attempt == null || _disposed) return;
    final attempt = Map<String, dynamic>.from(_attempt!);
    _sending = true;
    submission = KnowledgeSubmission.submitting;
    message = null;
    _notify();
    await _persist(attempt);
    try {
      for (var retry = 0; retry < 2; retry++) {
        if (_disposed) return;
        if (knowledgeInt(attempt['roundId']) != roundId) {
          _attempt = null;
          await _persist(null);
          return;
        }
        final watch = Stopwatch()..start();
        try {
          final receipt = await api.answerKnowledgeQuestion(
            matchId,
            roundId: knowledgeInt(attempt['roundId']),
            questionId: knowledgeInt(attempt['questionId']),
            answerIndex: knowledgeInt(attempt['answerIndex']),
            districtId: '${attempt['districtId']}',
            idempotencyKey: '${attempt['idempotencyKey']}',
            clientElapsedMs: attempt['clientElapsedMs'] == null
                ? null
                : knowledgeInt(attempt['clientElapsedMs']),
          );
          _confirm(receipt, attempt);
          return;
        } catch (error) {
          if (_disposed) return;
          // A late failure belongs to its original round, not the new question.
          if (knowledgeInt(attempt['roundId']) != roundId) {
            _attempt = null;
            await _persist(null);
            return;
          }
          final code = knowledgeErrorCode(error);
          debugPrint(
            'knowledge_answer type=${error is DioException ? error.type.name : error.runtimeType} code=$code http=${error is DioException ? error.response?.statusCode : null} trace=${attempt['idempotencyKey']} durationMs=${watch.elapsedMilliseconds}',
          );
          message = knowledgeErrorText(error);
          final terminal = {
            '401',
            '403',
            '404',
            '426',
            'GAME_UPDATE_REQUIRED',
            'UNAUTHORIZED',
            'INVALID_TOKEN',
            'TOKEN_EXPIRED',
            'ANSWER_INVALID',
            'DISTRICT_INVALID',
          }.contains(code);
          if (terminal) {
            _sessionExpired =
                error is DioException && error.response?.statusCode == 401;
            submission = KnowledgeSubmission.failed;
            _attempt = null;
            await _persist(null);
            return;
          }
          submission = KnowledgeSubmission.reconciling;
          _notify();
          try {
            final saved = await api.knowledgeAttempt(
              matchId,
              '${attempt['idempotencyKey']}',
            );
            if (saved['submitted'] == true) {
              _confirm(saved, attempt);
              return;
            }
          } catch (_) {
            /* A failed status lookup is not proof the answer was lost. */
          }
          if (knowledgeInt(attempt['roundId']) != roundId) {
            _attempt = null;
            await _persist(null);
            return;
          }
          if ({
            'ROUND_CLOSED',
            'QUESTION_EXPIRED',
            'STALE_QUESTION',
            'ANSWER_ALREADY_RECORDED',
            'IDEMPOTENCY_CONFLICT',
            'QUESTION_NOT_OPEN',
          }.contains(code)) {
            _attempt = null;
            await _persist(null);
            submission = KnowledgeSubmission.closed;
            await refresh();
            return;
          }
          if (retry == 0) {
            await Future<void>.delayed(
              Duration(milliseconds: 450 + Random().nextInt(200)),
            );
          }
        }
      }
      message =
          'لم يصل تأكيد الحفظ بعد. اضغط التحقق من الإجابة؛ لن نرسل اختيارًا مختلفًا.';
      submission = KnowledgeSubmission.reconciling;
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _confirm(Map<String, dynamic> receipt, Map<String, dynamic> attempt) {
    if (_disposed) return;
    if (receipt['submitted'] != true ||
        knowledgeInt(receipt['roundId']) != knowledgeInt(attempt['roundId']) ||
        knowledgeInt(receipt['questionId']) !=
            knowledgeInt(attempt['questionId']) ||
        receipt['idempotencyKey'] != attempt['idempotencyKey']) {
      throw const FormatException('INVALID_KNOWLEDGE_RECEIPT');
    }
    if (knowledgeInt(attempt['roundId']) == roundId) {
      submission = KnowledgeSubmission.confirmed;
      message = null;
      snapshot = {
        ...snapshot,
        'answered': true,
        'ownAnswer': {...attempt, ...receipt},
      };
    }
    _attempt = null;
    unawaited(_persist(null));
    _notify();
  }

  Future<void> reconcile() async {
    if (_sending || _disposed) return;
    if (_attempt == null) {
      await refresh();
      return;
    }
    try {
      final attempt = Map<String, dynamic>.from(_attempt!);
      final saved = await api.knowledgeAttempt(
        matchId,
        '${attempt['idempotencyKey']}',
      );
      if (saved['submitted'] == true) {
        _confirm(saved, attempt);
        return;
      }
      await refresh();
      if (_attempt != null &&
          knowledgeInt(attempt['roundId']) == roundId &&
          deadline != null &&
          serverNow.isBefore(deadline!)) {
        await _sendAttempt();
      } else {
        _attempt = null;
        await _persist(null);
      }
    } catch (error) {
      message = knowledgeErrorText(error);
      offline = true;
      _notify();
    }
  }

  void setActive(bool active) {
    _active = active;
    if (!active) {
      _fallback?.cancel();
      _boundary?.cancel();
      unawaited(_events?.cancel());
      _events = null;
    } else {
      unawaited(_bind());
      unawaited(refresh().then((_) => reconcile()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _fallback?.cancel();
    _boundary?.cancel();
    _clock.stop();
    unawaited(_events?.cancel());
    super.dispose();
  }
}
