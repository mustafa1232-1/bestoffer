import 'package:dio/dio.dart';

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

  Future<Map<String, dynamic>> getPostById(int postId) async {
    final response = await dio.get('/api/feed/posts/$postId');
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
  }) async {
    final payload = <String, dynamic>{'caption': caption};

    final response = mediaFile == null
        ? await dio.post('/api/feed/stories', data: payload)
        : await dio.post(
            '/api/feed/stories',
            data: FormData.fromMap({
              ...payload,
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
}
