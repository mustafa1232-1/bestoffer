import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/state/knowledge_match_controller.dart';

Map<String, dynamic> knowledgeFixture({
  int round = 1,
  int version = 2,
  bool answered = false,
}) {
  final now = DateTime.now().toUtc();
  return {
    'myUserId': 7,
    'protocolVersion': 2,
    'stateVersion': version,
    'serverTime': now.toIso8601String(),
    'phase': 'question_open',
    'round': {
      'id': round,
      'startsAt': now.subtract(const Duration(seconds: 2)).toIso8601String(),
      'deadlineAt': now.add(const Duration(seconds: 20)).toIso8601String(),
    },
    'match': {
      'id': 1,
      'status': 'active',
      'questionNumber': round - 1,
      'mySide': 'a',
      'teamSize': 1,
      'teams': {
        'a': {'id': 3, 'name': 'فريق دجلة', 'score': 150, 'members': []},
        'b': {'id': 4, 'name': 'فريق النخيل', 'score': 100, 'members': []},
      },
      'territories': {
        'a': ['garden'],
        'b': ['bridge'],
      },
      'availableDistricts': [
        {'id': 'souk', 'nameAr': 'سوق المعرفة'},
      ],
      'districts': [
        {
          'id': 'souk',
          'nameAr': 'سوق المعرفة',
          'neighbors': ['river', 'garden'],
        },
        {
          'id': 'river',
          'nameAr': 'درب دجلة',
          'neighbors': ['souk', 'old-city', 'bridge'],
        },
        {
          'id': 'garden',
          'nameAr': 'حدائق مسلكي',
          'neighbors': ['souk', 'library', 'market'],
        },
        {
          'id': 'old-city',
          'nameAr': 'المدينة القديمة',
          'neighbors': ['river', 'library', 'crafts'],
        },
        {
          'id': 'bridge',
          'nameAr': 'جسر الأصدقاء',
          'neighbors': ['river', 'market', 'science'],
        },
        {
          'id': 'library',
          'nameAr': 'دار الحكايات',
          'neighbors': ['garden', 'old-city', 'science'],
        },
        {
          'id': 'market',
          'nameAr': 'ساحة التحدي',
          'neighbors': ['garden', 'bridge', 'sports'],
        },
        {
          'id': 'crafts',
          'nameAr': 'خان الحرف',
          'neighbors': ['old-city', 'science', 'arts'],
        },
        {
          'id': 'science',
          'nameAr': 'مرصد الرافدين',
          'neighbors': ['bridge', 'library', 'crafts', 'sports'],
        },
        {
          'id': 'sports',
          'nameAr': 'ملعب الأبطال',
          'neighbors': ['market', 'science', 'arts'],
        },
        {
          'id': 'arts',
          'nameAr': 'مسرح النخيل',
          'neighbors': ['crafts', 'sports'],
        },
      ],
    },
    'question': {
      'id': round + 100,
      'text': 'أي مدينة عراقية تُعرف بمدينة العلم والعلماء؟',
      'categoryLabel': 'العراق',
      'scoring': {
        'basePoints': 150,
        'maxSpeedBonus': 50,
        'territoryBonusPoints': 0,
      },
      'options': ['بغداد', 'النجف', 'البصرة', 'الموصل'],
    },
    'answered': answered,
    'ownAnswer': answered
        ? {
            'roundId': round,
            'answerIndex': 1,
            'districtId': 'souk',
            'submitted': true,
          }
        : null,
    'lastAnswer': {'submitted': answered ? 1 : 0, 'total': 1},
    'chat': {
      'messages': [],
      'publicEnabled': false,
      'consent': {},
      'reactions': [],
    },
  };
}

class MemoryKnowledgeStore implements KnowledgeAttemptStore {
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, Map<String, dynamic>? value) async {
    if (value == null) {
      values.remove(scope);
    } else {
      values[scope] = Map.of(value);
    }
  }
}

class KnowledgeFakeApi extends GamesApi {
  KnowledgeFakeApi() : super(Dio());
  Map<String, dynamic> value = knowledgeFixture();
  Map<String, dynamic>? saved;
  Object? answerError;
  bool loseReply = false;
  int answers = 0, reads = 0;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> knowledgeMatch(int matchId) async {
    reads++;
    return Map.of(value);
  }

  int? lastClientElapsedMs;

  @override
  Future<Map<String, dynamic>> answerKnowledgeQuestion(
    int matchId, {
    required int answerIndex,
    required String districtId,
    required int roundId,
    required int questionId,
    required String idempotencyKey,
    int? clientElapsedMs,
  }) async {
    answers++;
    lastClientElapsedMs = clientElapsedMs;
    if (answerError != null) throw answerError!;
    saved = {
      'submitted': true,
      'roundId': roundId,
      'questionId': questionId,
      'idempotencyKey': idempotencyKey,
    };
    if (loseReply) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.receiveTimeout,
      );
    }
    return pending?.future ?? saved!;
  }

  @override
  Future<Map<String, dynamic>> knowledgeAttempt(
    int matchId,
    String key,
  ) async => saved ?? {'submitted': false};
}

class KnowledgeFakeRealtime implements MaslakiRealtimeClient {
  final events = StreamController<MaslakiRealtimeEvent>.broadcast();
  int subscriptions = 0;
  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async {
    subscriptions++;
    return events.stream;
  }

  @override
  Future<bool> bindAuthenticatedSession({bool force = false}) async => true;
  @override
  Future<void> clearSession() async {}
  @override
  Future<void> setAppActive(bool active) async {}
  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(
    String namespace,
  ) => subscribeDefaultUserChannel();
  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeTopic(String topic) =>
      subscribeDefaultUserChannel();
}

DioException rejection(int status, String code) => DioException(
  requestOptions: RequestOptions(),
  response: Response(
    requestOptions: RequestOptions(),
    statusCode: status,
    data: {'code': code},
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  test('the on-device reaction time is measured and sent with the answer', () async {
    final api = KnowledgeFakeApi();
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
    );
    addTearDown(c.dispose);
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    c.selectDistrict('souk');
    c.selectAnswer(1);
    await c.submit();
    expect(api.lastClientElapsedMs, isNotNull);
    expect(api.lastClientElapsedMs, greaterThanOrEqualTo(100));
    expect(api.lastClientElapsedMs, lessThan(5000));
  });
  test('auto submit sends once, the moment both choices exist', () async {
    final api = KnowledgeFakeApi();
    (api.value['match'] as Map)['availableDistricts'] = [
      {'id': 'souk', 'nameAr': 'سوق المعرفة'},
      {'id': 'arts', 'nameAr': 'مسرح النخيل'},
    ];
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
      autoSubmit: true,
    );
    addTearDown(c.dispose);
    await c.start();
    c.selectAnswer(1);
    await Future<void>.delayed(Duration.zero);
    expect(api.answers, 0, reason: 'no district yet: nothing is sent');
    c.selectDistrict('souk');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.answers, 1);
    expect(c.submission, KnowledgeSubmission.confirmed);
    c.selectAnswer(2);
    await c.submit();
    expect(api.answers, 1, reason: 'a confirmed answer is final');
  });
  test('auto submit picks the only remaining district', () async {
    final api = KnowledgeFakeApi();
    (api.value['match'] as Map)['availableDistricts'] = [
      {'id': 'arts', 'nameAr': 'مسرح النخيل'},
    ];
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
      autoSubmit: true,
    );
    addTearDown(c.dispose);
    await c.start();
    expect(c.selectedDistrict, 'arts');
    c.selectAnswer(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.answers, 1);
  });
  test('confirmed only after persistence, duplicate tap sends once', () async {
    final api = KnowledgeFakeApi()..pending = Completer();
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
    );
    addTearDown(c.dispose);
    await c.start();
    c.selectDistrict('souk');
    c.selectAnswer(1);
    final send = c.submit();
    await Future<void>.delayed(Duration.zero);
    expect(c.submission, KnowledgeSubmission.submitting);
    expect(c.snapshot['answered'], false);
    await c.submit();
    expect(api.answers, 1);
    api.pending!.complete(api.saved!);
    await send;
    expect(c.submission, KnowledgeSubmission.confirmed);
    expect(c.snapshot['answered'], true);
  });
  test(
    'a lost HTTP response reconciles the saved answer without resubmission',
    () async {
      final api = KnowledgeFakeApi()..loseReply = true;
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      c.selectDistrict('souk');
      c.selectAnswer(1);
      await c.submit();
      expect(c.submission, KnowledgeSubmission.confirmed);
      expect(api.answers, 1);
    },
  );
  test(
    'stale snapshots and late receipts cannot return to a previous round',
    () async {
      final api = KnowledgeFakeApi()..pending = Completer();
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      c.selectDistrict('souk');
      c.selectAnswer(1);
      final send = c.submit();
      await Future<void>.delayed(Duration.zero);
      c.applySnapshot(knowledgeFixture(round: 2, version: 4));
      c.applySnapshot(knowledgeFixture(round: 1, version: 2));
      api.pending!.complete(api.saved!);
      await send;
      expect(c.roundId, 2);
      expect(c.submission, KnowledgeSubmission.idle);
      expect(c.selectedAnswer, isNull);
    },
  );
  test(
    'realtime is single, duplicates deduplicate, resume resynchronizes',
    () async {
      final rt = KnowledgeFakeRealtime(), api = KnowledgeFakeApi();
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        realtime: rt,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(() async {
        c.dispose();
        await rt.events.close();
      });
      await c.start();
      final event = const MaslakiRealtimeEvent(
        topic: 'user:7',
        event: 'knowledge_round_started',
        data: {'matchId': 1, 'stateVersion': 3, 'eventId': 9},
        envelope: {},
      );
      rt.events.add(event);
      rt.events.add(event);
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, 2);
      expect(rt.subscriptions, 1);
      c.setActive(false);
      c.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, greaterThan(2));
      expect(rt.subscriptions, 2);
    },
  );
  test('401 does not create an answer retry storm', () async {
    final api = KnowledgeFakeApi()
      ..answerError = rejection(401, 'UNAUTHORIZED');
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
    );
    addTearDown(c.dispose);
    await c.start();
    c.selectDistrict('souk');
    c.selectAnswer(1);
    await c.submit();
    expect(api.answers, 1);
    expect(c.submission, KnowledgeSubmission.failed);
    expect(c.message, contains('سجّل الدخول'));
    expect(c.canSelect, false);
  });
  test('late rejection cannot disable the next round', () async {
    final api = KnowledgeFakeApi()..pending = Completer();
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
    );
    addTearDown(c.dispose);
    await c.start();
    c.selectDistrict('souk');
    c.selectAnswer(1);
    final send = c.submit();
    await Future<void>.delayed(Duration.zero);
    c.applySnapshot(knowledgeFixture(round: 2, version: 4));
    api.pending!.completeError(rejection(409, 'ROUND_CLOSED'));
    await send;
    expect(c.roundId, 2);
    expect(c.submission, KnowledgeSubmission.idle);
    expect(c.canSelect, true);
    expect(c.pendingAttempt, isEmpty);
  });
  test(
    'countdown rejection allows selection after the question opens',
    () async {
      final api = KnowledgeFakeApi()
        ..answerError = rejection(409, 'QUESTION_NOT_OPEN');
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      c.selectDistrict('souk');
      c.selectAnswer(1);
      await c.submit();
      expect(c.canSubmit, true);
      expect(c.submission, KnowledgeSubmission.selected);
    },
  );
  test('a same-version pre-commit snapshot cannot erase a receipt', () async {
    final api = KnowledgeFakeApi();
    final c = KnowledgeMatchController(
      api: api,
      matchId: 1,
      store: MemoryKnowledgeStore(),
      polling: false,
    );
    addTearDown(c.dispose);
    await c.start();
    c.selectDistrict('souk');
    c.selectAnswer(1);
    await c.submit();
    c.applySnapshot(knowledgeFixture());
    expect(c.submission, KnowledgeSubmission.confirmed);
    expect(c.snapshot['answered'], true);
    expect(c.canSubmit, false);
  });
  test(
    'process restoration finds persisted attempt under the authenticated player scope',
    () async {
      final store = MemoryKnowledgeStore();
      store.values['7.1'] = {
        'roundId': 1,
        'questionId': 101,
        'idempotencyKey': 'saved_attempt_key',
        'answerIndex': 1,
        'districtId': 'souk',
      };
      final api = KnowledgeFakeApi()
        ..saved = {
          'submitted': true,
          'roundId': 1,
          'questionId': 101,
          'idempotencyKey': 'saved_attempt_key',
        };
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: store,
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.submission, KnowledgeSubmission.confirmed);
      expect(api.answers, 0);
    },
  );
  test(
    'deadline is enforced locally without trusting a device wall clock',
    () async {
      final api = KnowledgeFakeApi();
      api.value['serverTime'] = DateTime.utc(2099).toIso8601String();
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      c.selectDistrict('souk');
      c.selectAnswer(1);
      await c.submit();
      expect(api.answers, 0);
      expect(c.canSelect, false);
    },
  );
}
