import 'package:dio/dio.dart';
import 'dart:convert';

import '../../../core/files/local_media_file.dart';

class SocialApi {
  final Dio dio;

  SocialApi(this.dio);

  Future<Map<String, dynamic>> listPosts({
    int limit = 20,
    int? beforeId,
    String? kind,
  }) async {
    final query =
        <String, dynamic>{
          'limit': limit,
          'beforeId': beforeId,
          'kind': kind?.trim(),
        }..removeWhere((key, value) {
          if (value == null) return true;
          if (key == 'kind' && (value as String).isEmpty) return true;
          return false;
        });

    final response = await dio.get('/api/feed/posts', queryParameters: query);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listStories({
    int limitUsers = 30,
    int maxPerUser = 8,
  }) async {
    final response = await dio.get(
      '/api/feed/stories',
      queryParameters: {'limitUsers': limitUsers, 'maxPerUser': maxPerUser},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyStoryArchive({
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/stories/archive/me',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPostById(int postId) async {
    final response = await dio.get('/api/feed/posts/$postId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getUserProfile(int userId) async {
    final response = await dio.get('/api/feed/users/$userId/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getUserRelation(int userId) async {
    final response = await dio.get('/api/feed/users/$userId/relation');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMyProfile({
    String? fullName,
    String? bio,
    int? age,
    String? imageUrl,
    bool? showPhone,
    bool? postsPublic,
    bool? storiesPublic,
    LocalMediaFile? imageFile,
  }) async {
    final payload = <String, dynamic>{
      'fullName': fullName,
      'bio': bio,
      'age': age,
      'imageUrl': imageUrl,
      'showPhone': showPhone,
      'postsPublic': postsPublic,
      'storiesPublic': storiesPublic,
    }..removeWhere((_, value) => value == null);

    final response = imageFile == null
        ? await dio.patch('/api/feed/profile/me', data: payload)
        : await dio.patch(
            '/api/feed/profile/me',
            data: FormData.fromMap({
              ...payload,
              'imageFile': await imageFile.toMultipartFile(),
            }),
          );

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserHighlights(int userId) async {
    final response = await dio.get('/api/feed/users/$userId/highlights');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addStoryHighlight(
    int storyId, {
    String? title,
  }) async {
    final payload = <String, dynamic>{'title': title}
      ..removeWhere((_, value) => value == null);
    final response = await dio.post(
      '/api/feed/stories/$storyId/highlight',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> removeStoryHighlight(int highlightId) async {
    await dio.delete('/api/feed/highlights/$highlightId');
  }

  Future<Map<String, dynamic>> listUserPosts({
    required int userId,
    int limit = 20,
    int? beforeId,
    String? kind,
  }) async {
    final query =
        <String, dynamic>{
          'limit': limit,
          'beforeId': beforeId,
          'kind': kind?.trim(),
        }..removeWhere((key, value) {
          if (value == null) return true;
          if (key == 'kind' && (value as String).isEmpty) return true;
          return false;
        });

    final response = await dio.get(
      '/api/feed/users/$userId/posts',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPost({
    required String caption,
    required String postKind,
    int? merchantId,
    int? reviewRating,
    LocalMediaFile? mediaFile,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      'postKind': postKind,
      'merchantId': merchantId,
      'reviewRating': reviewRating,
    }..removeWhere((_, value) => value == null);

    final response = mediaFile == null
        ? await dio.post('/api/feed/posts', data: payload)
        : await dio.post(
            '/api/feed/posts',
            data: FormData.fromMap({
              ...payload,
              'mediaFile': await mediaFile.toMultipartFile(),
            }),
          );

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createStory({
    required String caption,
    LocalMediaFile? mediaFile,
    Map<String, dynamic>? storyStyle,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      'storyStyle': storyStyle,
    }..removeWhere((_, value) => value == null);

    final response = mediaFile == null
        ? await dio.post('/api/feed/stories', data: payload)
        : await dio.post(
            '/api/feed/stories',
            data: FormData.fromMap({
              ...payload,
              if (storyStyle != null) 'storyStyle': jsonEncode(storyStyle),
              'mediaFile': await mediaFile.toMultipartFile(),
            }),
          );

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> markStoryViewed(int storyId) async {
    await dio.post('/api/feed/stories/$storyId/view');
  }

  Future<Map<String, dynamic>> toggleLike(int postId) async {
    final response = await dio.post('/api/feed/posts/$postId/like');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listComments(
    int postId, {
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);

    final response = await dio.get(
      '/api/feed/posts/$postId/comments',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addComment(int postId, String body) async {
    final response = await dio.post(
      '/api/feed/posts/$postId/comments',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMerchants({
    String search = '',
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/feed/merchants',
      queryParameters: {'search': search, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listThreads() async {
    final response = await dio.get('/api/feed/chats/threads');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createThread(int userId) async {
    final response = await dio.post(
      '/api/feed/chats/threads',
      data: {'userId': userId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listThreadMessages(
    int threadId, {
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);

    final response = await dio.get(
      '/api/feed/chats/threads/$threadId/messages',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendThreadMessage(
    int threadId,
    String body,
  ) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/messages',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> toggleThreadMessageReaction({
    required int threadId,
    required int messageId,
    String reaction = 'like',
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/messages/$messageId/reaction',
      data: {'reaction': reaction},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendRelationRequest(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/request');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptRelationRequest(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/accept');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectRelationRequest(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/reject');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelRelationRequest(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/cancel');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> removeRelation(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/remove');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> blockRelation(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/block');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> unblockRelation(int userId) async {
    final response = await dio.post('/api/feed/users/$userId/relation/unblock');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listIncomingRelationRequests({
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/feed/relations/incoming',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listOutgoingRelationRequests({
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/feed/relations/outgoing',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getThreadCallState({
    required int threadId,
    int signalLimit = 160,
  }) async {
    final response = await dio.get(
      '/api/feed/chats/threads/$threadId/call',
      queryParameters: {'signalLimit': signalLimit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startThreadCall({required int threadId}) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/call/start',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendThreadCallSignal({
    required int threadId,
    int? sessionId,
    required String signalType,
    Map<String, dynamic>? signalPayload,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/call/signal',
      data: <String, dynamic>{
        'sessionId': sessionId,
        'signalType': signalType,
        'signalPayload': signalPayload,
      }..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endThreadCall({
    required int threadId,
    String status = 'ended',
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/call/end',
      data: {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
