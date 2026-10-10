import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

final gamesApiProvider = Provider<GamesApi>((ref) {
  return GamesApi(ref.read(dioClientProvider).dio);
});

class GamesApi {
  final Dio dio;

  const GamesApi(this.dio);

  Future<Map<String, dynamic>> status() => _get('/api/games/status');

  Future<Map<String, dynamic>> createRoom(String mode) =>
      _post('/api/games/rooms', {'mode': mode});

  Future<Map<String, dynamic>> joinRoom(String code) =>
      _post('/api/games/rooms/join', {'code': code.trim().toUpperCase()});

  Future<Map<String, dynamic>> snapshot(int roomId) =>
      _get('/api/games/rooms/$roomId');

  Future<Map<String, dynamic>> setReady(int roomId, bool ready) =>
      _post('/api/games/rooms/$roomId/ready', {'ready': ready});

  Future<Map<String, dynamic>> start(int roomId) =>
      _post('/api/games/rooms/$roomId/start', const {});

  Future<Map<String, dynamic>> attempt(
    int roomId, {
    required String code,
    required String commandId,
  }) => _post('/api/games/rooms/$roomId/attempt', {
    'code': code,
    'commandId': commandId,
  });

  Future<Map<String, dynamic>> hint(int roomId, String commandId) =>
      _post('/api/games/rooms/$roomId/hint', {'commandId': commandId});

  Future<Map<String, dynamic>> propose(
    int roomId, {
    required String kind,
    String? code,
    required String commandId,
  }) => _post('/api/games/rooms/$roomId/proposals', {
    'kind': kind,
    'code': ?code,
    'commandId': commandId,
  });

  Future<Map<String, dynamic>> vote(int roomId, int proposalId, String vote) =>
      _post('/api/games/rooms/$roomId/proposals/$proposalId/vote', {
        'vote': vote,
      });

  Future<void> message(int roomId, String body) async {
    await dio.post('/api/games/rooms/$roomId/messages', data: {'body': body});
  }

  Future<void> heartbeat(int roomId) async {
    await dio.post('/api/games/rooms/$roomId/heartbeat', data: const {});
  }

  Future<Map<String, dynamic>> teamCodeVoiceToken(int roomId) =>
      _post('/api/games/rooms/$roomId/voice-token', const {});

  Future<void> leave(int roomId) async {
    await dio.post('/api/games/rooms/$roomId/leave', data: const {});
  }

  Future<Map<String, dynamic>> continueSolo(int roomId) =>
      _post('/api/games/rooms/$roomId/continue-solo', const {});

  Future<List<Map<String, dynamic>>> history() async {
    final response = await dio.get('/api/games/history');
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> claimReward(int sessionId) =>
      _post('/api/games/sessions/$sessionId/reward', const {});

  Future<Map<String, dynamic>> createMafiaRoom({
    String ruleset = 'standard',
    String pace = 'classic',
    String tableTheme = 'emerald',
    int maxPlayers = 14,
    bool revealRolesOnDeath = true,
  }) => _post('/api/games/mafia/rooms', {
    'ruleset': ruleset,
    'pace': pace,
    'tableTheme': tableTheme,
    'maxPlayers': maxPlayers,
    'revealRolesOnDeath': revealRolesOnDeath,
  });

  Future<Map<String, dynamic>> joinMafiaRoom(String code) =>
      _post('/api/games/mafia/rooms/join', {'code': code.trim().toUpperCase()});

  Future<Map<String, dynamic>> mafiaSnapshot(int roomId) =>
      _get('/api/games/mafia/rooms/$roomId');

  Future<Map<String, dynamic>> setMafiaReady(int roomId, bool ready) =>
      _post('/api/games/mafia/rooms/$roomId/ready', {'ready': ready});

  Future<Map<String, dynamic>> startMafia(int roomId) =>
      _post('/api/games/mafia/rooms/$roomId/start', const {});

  Future<Map<String, dynamic>> acknowledgeMafiaRole(int roomId) =>
      _post('/api/games/mafia/rooms/$roomId/acknowledge-role', const {});

  Future<Map<String, dynamic>> mafiaAction(
    int roomId, {
    required String type,
    int? targetPlayerId,
    required String commandId,
    int? phaseVersion,
  }) => _post('/api/games/mafia/rooms/$roomId/actions', {
    'type': type,
    'targetPlayerId': ?targetPlayerId,
    'commandId': commandId,
    'phaseVersion': ?phaseVersion,
  });

  Future<Map<String, dynamic>> advanceMafia(int roomId) =>
      _post('/api/games/mafia/rooms/$roomId/advance', const {});

  Future<Map<String, dynamic>> sendMafiaMessage(
    int roomId, {
    required String body,
    required String channel,
    String? clientMessageId,
  }) => _post('/api/games/mafia/rooms/$roomId/messages', {
    'body': body,
    'channel': channel,
    'clientMessageId': ?clientMessageId,
  });

  Future<Map<String, dynamic>> sendMafiaInteraction(
    int roomId, {
    required String kind,
    int? targetPlayerId,
    required String commandId,
  }) => _post('/api/games/mafia/rooms/$roomId/interactions', {
    'kind': kind,
    'targetPlayerId': ?targetPlayerId,
    'commandId': commandId,
  });

  Future<Map<String, dynamic>> reportMafiaPlayer(
    int roomId, {
    required int targetPlayerId,
    required String reason,
    String? details,
    required String commandId,
  }) => _post('/api/games/mafia/rooms/$roomId/reports', {
    'targetPlayerId': targetPlayerId,
    'reason': reason,
    'details': ?details,
    'commandId': commandId,
  });

  Future<void> mafiaHeartbeat(int roomId) async {
    await dio.post('/api/games/mafia/rooms/$roomId/heartbeat', data: const {});
  }

  Future<Map<String, dynamic>> mafiaVoiceToken(int roomId) =>
      _post('/api/games/mafia/rooms/$roomId/voice-token', const {});

  Future<Map<String, dynamic>> kickMafiaPlayer(int roomId, int playerId) async {
    final response = await dio.delete(
      '/api/games/mafia/rooms/$roomId/players/$playerId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> closeMafiaRoom(int roomId) =>
      _post('/api/games/mafia/rooms/$roomId/close', const {});

  Future<Map<String, dynamic>> reactivateMafiaRoom(
    int roomId, {
    required String ruleset,
    String pace = 'classic',
    String tableTheme = 'emerald',
    required int maxPlayers,
    bool revealRolesOnDeath = true,
  }) => _post('/api/games/mafia/rooms/$roomId/reactivate', {
    'ruleset': ruleset,
    'pace': pace,
    'tableTheme': tableTheme,
    'maxPlayers': maxPlayers,
    'revealRolesOnDeath': revealRolesOnDeath,
  });

  Future<void> leaveMafia(int roomId) async {
    await dio.post('/api/games/mafia/rooms/$roomId/leave', data: const {});
  }

  Future<List<Map<String, dynamic>>> mafiaHistory() async {
    final response = await dio.get('/api/games/mafia/history');
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> adminOverview() =>
      _get('/api/games/admin/overview');

  Future<List<Map<String, dynamic>>> mafiaReports({int limit = 50}) async {
    final response = await dio.get(
      '/api/games/admin/mafia-reports',
      queryParameters: {'limit': limit},
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> reviewMafiaReport(
    int reportId, {
    String? note,
  }) => _patch('/api/games/admin/mafia-reports/$reportId/review', {
    'note': ?note,
  });

  Future<Map<String, dynamic>> updateCampaign({
    required bool enabled,
    String? rewardType,
    DateTime? startsAt,
    DateTime? endsAt,
    num? rewardValue,
    int? rewardValidDays,
    int? claimLimit,
  }) => _patch('/api/games/admin/campaign', {
    'enabled': enabled,
    'rewardType': ?rewardType,
    if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
    if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
    'rewardValue': ?rewardValue,
    'rewardValidDays': ?rewardValidDays,
    'claimLimit': ?claimLimit,
  });

  Future<List<Map<String, dynamic>>> knowledgeEvents() async {
    final response = await dio.get('/api/games/knowledge/events');
    return _maps(response.data);
  }

  Future<Map<String, dynamic>> createKnowledgeDuel({
    int teamSize = 1,
    bool isPrivate = false,
    int bestOf = 3,
  }) => _post('/api/games/knowledge/duels', {
    'teamSize': teamSize,
    'title': 'تحدي خريطة المعرفة',
    'isPrivate': isPrivate,
    'bestOf': bestOf,
  });

  Future<Map<String, dynamic>> lookupKnowledgeRoom(String code) => _post(
    '/api/games/knowledge/rooms/lookup',
    {'code': code.trim().toUpperCase()},
  );

  Future<Map<String, dynamic>> knowledgeRoom(
    int eventId, {
    String? code,
  }) => _get(
    '/api/games/knowledge/rooms/$eventId${code == null ? '' : '?code=${Uri.encodeQueryComponent(code)}'}',
  );

  Future<Map<String, dynamic>> joinKnowledgeRoomSeat(
    int eventId, {
    required String side,
    String? code,
  }) => _post('/api/games/knowledge/rooms/$eventId/seats', {
    'side': side,
    'code': ?code,
  });

  Future<Map<String, dynamic>> closeKnowledgeRoom(int eventId) =>
      _post('/api/games/knowledge/rooms/$eventId/close', const {});

  Future<Map<String, dynamic>> reactivateKnowledgeRoom(int eventId) =>
      _post('/api/games/knowledge/rooms/$eventId/reactivate', const {});

  Future<Map<String, dynamic>> registerKnowledgeTeam(
    int eventId, {
    required String name,
  }) => _post('/api/games/knowledge/teams', {'eventId': eventId, 'name': name});

  Future<Map<String, dynamic>> joinKnowledgeTeam(String code) => _post(
    '/api/games/knowledge/teams/join',
    {'code': code.trim().toUpperCase()},
  );

  Future<List<Map<String, dynamic>>> knowledgeMatches(int eventId) async {
    final response = await dio.get(
      '/api/games/knowledge/events/$eventId/matches',
    );
    return _maps(response.data);
  }

  Future<Map<String, dynamic>> knowledgeMatch(int matchId) =>
      _get('/api/games/knowledge/matches/$matchId');

  Future<Map<String, dynamic>> knowledgeBracket(int eventId) =>
      _get('/api/games/knowledge/events/$eventId/bracket');

  Future<Map<String, dynamic>> leaveKnowledgeSeat(int eventId) =>
      _post('/api/games/knowledge/events/$eventId/leave-seat', const {});

  Future<Map<String, dynamic>> answerKnowledgeQuestion(
    int matchId, {
    required int answerIndex,
    required String districtId,
    required int roundId,
    required int questionId,
    required String idempotencyKey,
  }) async {
    final response = await dio.post(
      '/api/games/knowledge/matches/$matchId/answers',
      data: {
        'answerIndex': answerIndex,
        'districtId': districtId,
        'roundId': roundId,
        'questionId': questionId,
        'idempotencyKey': idempotencyKey,
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 8),
        extra: {'skipBaseUrlFallback': true},
        headers: {'X-Request-ID': idempotencyKey},
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> knowledgeAttempt(int matchId, String key) =>
      _get('/api/games/knowledge/matches/$matchId/attempts/$key');

  Future<Map<String, dynamic>> sendKnowledgeMessage(
    int matchId, {
    required String channel,
    required String body,
  }) => _post('/api/games/knowledge/matches/$matchId/chat', {
    'channel': channel,
    'body': body,
  });

  Future<Map<String, dynamic>> setKnowledgePublicChatConsent(
    int matchId,
    bool enabled,
  ) => _post('/api/games/knowledge/matches/$matchId/chat-consent', {
    'enabled': enabled,
  });

  Future<Map<String, dynamic>> reactKnowledgeMatch(int matchId, String kind) =>
      _post('/api/games/knowledge/matches/$matchId/reactions', {'kind': kind});

  Future<Map<String, dynamic>> knowledgeVoiceToken(
    int matchId,
    String channel,
  ) => _post('/api/games/knowledge/matches/$matchId/voice-token', {
    'channel': channel,
  });

  Future<Map<String, dynamic>> knowledgeAdminOverview() =>
      _get('/api/games/admin/knowledge/overview');

  Future<List<Map<String, dynamic>>> knowledgeAdminQuestions({
    String? category,
    String? difficulty,
    String? query,
    int limit = 100,
  }) async {
    final response = await dio.get(
      '/api/games/admin/knowledge/questions',
      queryParameters: {
        'category': ?category,
        'difficulty': ?difficulty,
        if (query != null && query.isNotEmpty) 'query': query,
        'limit': limit,
      },
    );
    return _maps(response.data);
  }

  Future<Map<String, dynamic>> createKnowledgeQuestion({
    required String category,
    required String difficulty,
    required String question,
    required List<String> options,
    required int answerIndex,
    String? explanation,
  }) => _post('/api/games/admin/knowledge/questions', {
    'category': category,
    'difficulty': difficulty,
    'question': question,
    'options': options,
    'answerIndex': answerIndex,
    'explanation': ?explanation,
  });

  Future<Map<String, dynamic>> setKnowledgeQuestionActive(
    int questionId,
    bool active,
  ) => _patch('/api/games/admin/knowledge/questions/$questionId', {
    'active': active,
  });

  Future<Map<String, dynamic>> createKnowledgeTournament({
    required String title,
    required int teamSize,
    required int maxTeams,
    int bestOf = 3,
    String? prizeTitle,
    String? prizeDescription,
    bool prizeIsMock = true,
    DateTime? startsAt,
    DateTime? endsAt,
  }) => _post('/api/games/admin/knowledge/events', {
    'title': title,
    'teamSize': teamSize,
    'maxTeams': maxTeams,
    'bestOf': bestOf,
    'prizeTitle': ?prizeTitle,
    'prizeDescription': ?prizeDescription,
    'prizeIsMock': prizeIsMock,
    if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
    if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
  });

  Future<Map<String, dynamic>> startKnowledgeTournament(int eventId) =>
      _post('/api/games/admin/knowledge/events/$eventId/start', const {});

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await dio.get(path);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.post(path, data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(path, data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const [];
}
