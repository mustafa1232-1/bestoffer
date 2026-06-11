import 'package:dio/dio.dart';

/// Assistant API wrapper.
///
/// Note: this service is intentionally kept isolated until the assistant UI is
/// re-enabled in production routing.
class AssistantApi {
  final Dio dio;

  AssistantApi(this.dio);

  Future<Map<String, dynamic>> chat({
    required String message,
    int? sessionId,
  }) async {
    final payload = <String, dynamic>{'message': message};
    if (sessionId != null) payload['sessionId'] = sessionId;
    final response = await dio.post(
      '/api/assistant/chat',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await dio.get('/api/assistant/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateHomePreferences({
    required Map<String, dynamic> preferences,
  }) async {
    final response = await dio.post(
      '/api/assistant/profile/home',
      data: preferences,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startNewSession() async {
    final response = await dio.post('/api/assistant/session/new');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getCurrentSession() async {
    final response = await dio.get('/api/assistant/session');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> recommendCommerce({
    required String query,
  }) async {
    final response = await dio.post(
      '/api/assistant/recommend/commerce',
      data: {'query': query},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> recommendJobs({
    required String query,
  }) async {
    final response = await dio.post(
      '/api/assistant/recommend/jobs',
      data: {'query': query},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> confirmDraft(String token) async {
    final response = await dio.post('/api/assistant/draft/$token/confirm');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> aiChat({
    required String message,
    int? sessionId,
    int? conversationId,
  }) async {
    final payload = <String, dynamic>{'message': message};
    final effectiveSessionId = sessionId ?? conversationId;
    if (effectiveSessionId != null) {
      payload['sessionId'] = effectiveSessionId;
    }
    final response = await dio.post(
      '/api/assistant/ai/chat',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listAiConversations({
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/assistant/ai/conversations',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final payload = Map<String, dynamic>.from(response.data as Map);
    final rows = List<dynamic>.from(payload['items'] as List? ?? const []);
    return rows.map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
  }

  Future<Map<String, dynamic>> getAiConversation(int conversationId) async {
    final response = await dio.get(
      '/api/assistant/ai/conversations/$conversationId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listAiMemories() async {
    final response = await dio.get('/api/assistant/ai/memories');
    final payload = Map<String, dynamic>.from(response.data as Map);
    final rows = List<dynamic>.from(payload['items'] as List? ?? const []);
    return rows.map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
  }

  Future<Map<String, dynamic>> createAiMemory({
    required String text,
    String? category,
  }) async {
    final memoryType = (category == null || category.trim().isEmpty)
        ? 'note'
        : category.trim();
    final payload = <String, dynamic>{'text': text};
    payload
      ..clear()
      ..addAll(<String, dynamic>{
        'memoryType': memoryType,
        'memoryKey': 'manual_${memoryType.toLowerCase()}',
        'memoryValue': text,
      });
    final response = await dio.post(
      '/api/assistant/ai/memories',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateAiMemory({
    required int memoryId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.patch(
      '/api/assistant/ai/memories/$memoryId',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteAiMemory(int memoryId) async {
    await dio.delete('/api/assistant/ai/memories/$memoryId');
  }

  Future<void> clearAiMemories() async {
    await dio.delete('/api/assistant/ai/memories');
  }

  Future<Map<String, dynamic>> setAiMemoryConsent({
    required bool enabled,
  }) async {
    final consentFlags = <String, dynamic>{
      'memoryEnabled': enabled,
      'profileStorage': enabled,
      'personalization': enabled,
      'adminReview': enabled,
      'improveModel': enabled,
    };
    final response = await dio.post(
      '/api/assistant/ai/memory/consent',
      data: {'consentFlags': consentFlags},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getAiUserProfile() async {
    final response = await dio.get('/api/assistant/ai/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateAiUserProfile({
    required Map<String, dynamic> payload,
  }) async {
    final response = await dio.patch('/api/assistant/ai/profile', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> appSearch({
    required String query,
  }) async {
    final response = await dio.post(
      '/api/assistant/ai/search/app',
      data: {'query': query},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> webSearch({
    required String query,
  }) async {
    final response = await dio.post(
      '/api/assistant/ai/search/web',
      data: {'query': query},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listAiTopics() async {
    final response = await dio.get('/api/assistant/ai/topics');
    final payload = Map<String, dynamic>.from(response.data as Map);
    final rows = List<dynamic>.from(payload['items'] as List? ?? const []);
    return rows.map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
  }
}
