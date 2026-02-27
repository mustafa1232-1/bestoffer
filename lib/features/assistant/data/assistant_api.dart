import 'package:dio/dio.dart';

class AssistantApi {
  final Dio dio;

  AssistantApi(this.dio);

  Future<Map<String, dynamic>> getCurrentSession({
    int? sessionId,
    int limit = 50,
  }) async {
    final response = await dio.get(
      '/api/assistant/session',
      queryParameters: {'sessionId': sessionId, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startNewSession() async {
    final response = await dio.post('/api/assistant/session/new');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await dio.get('/api/assistant/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateHomePreferences({
    String? audience,
    String? priority,
    List<String>? interests,
    bool? completed,
  }) async {
    final payload = <String, dynamic>{
      'audience': audience,
      'priority': priority,
      'interests': interests,
      'completed': completed,
    }..removeWhere((_, value) => value == null);

    final response = await dio.post(
      '/api/assistant/profile/home',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> chat({
    required String message,
    int? sessionId,
    int? addressId,
    bool createDraft = false,
    String? draftToken,
    bool confirmDraft = false,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/assistant/chat',
      data: {
        'message': message,
        'sessionId': sessionId,
        'addressId': addressId,
        'createDraft': createDraft,
        'draftToken': draftToken,
        'confirmDraft': confirmDraft,
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> confirmDraft({
    required String token,
    int? sessionId,
    int? addressId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/assistant/draft/$token/confirm',
      data: {'sessionId': sessionId, 'addressId': addressId, 'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
