import 'package:dio/dio.dart';
import 'dart:convert';

import '../core/local_media_file.dart';

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

  Future<Map<String, dynamic>> listMyArchivedPosts({
    int limit = 40,
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
      '/api/feed/archive/posts',
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

  Future<Map<String, dynamic>> setUserNotificationPreference({
    required int userId,
    required bool enabled,
  }) async {
    final response = await dio.patch(
      '/api/feed/users/$userId/notification-preference',
      data: {'enabled': enabled},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> runSuperAdminUserAction({
    required int userId,
    required String action,
  }) async {
    final response = await dio.post(
      '/api/feed/users/$userId/super-admin/action',
      data: {'action': action},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getUserRelation(int userId) async {
    final response = await dio.get('/api/feed/users/$userId/relation');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMyProfile({
    String? fullName,
    String? username,
    String? bio,
    int? age,
    String? imageUrl,
    String? workTitle,
    String? workCompany,
    bool? showPhone,
    bool? postsPublic,
    bool? storiesPublic,
    bool? relationsPublic,
    bool? accountPrivate,
    String? onlineStatusVisibility,
    String? lastSeenVisibility,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    LocalMediaFile? imageFile,
  }) async {
    final payload = <String, dynamic>{
      'fullName': fullName,
      'username': username,
      'bio': bio,
      'age': age,
      'imageUrl': imageUrl,
      'workTitle': workTitle,
      'workCompany': workCompany,
      'showPhone': showPhone,
      'postsPublic': postsPublic,
      'storiesPublic': storiesPublic,
      'relationsPublic': relationsPublic,
      'accountPrivate': accountPrivate,
      'onlineStatusVisibility': onlineStatusVisibility,
      'lastSeenVisibility': lastSeenVisibility,
      'readReceiptsEnabled': readReceiptsEnabled,
      'typingIndicatorsEnabled': typingIndicatorsEnabled,
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

  Future<Map<String, dynamic>> getMyResidenceChangeRequest() async {
    final response = await dio.get('/api/feed/profile/me/residence-change');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getMyActiveSocialRestrictions() async {
    final response = await dio.get('/api/feed/profile/me/social-restrictions');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> submitResidenceChangeRequest({
    required String block,
    required String buildingNumber,
    required String apartmentNumber,
    String? note,
    LocalMediaFile? documentImageFile,
  }) async {
    final payload = <String, dynamic>{
      'block': block.trim().toUpperCase(),
      'buildingNumber': buildingNumber.trim().toUpperCase(),
      'apartmentNumber': apartmentNumber.trim().toUpperCase(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
    };
    final response = documentImageFile == null
        ? await dio.post('/api/feed/profile/me/residence-change', data: payload)
        : await dio.post(
            '/api/feed/profile/me/residence-change',
            data: FormData.fromMap({
              ...payload,
              'documentImageFile': await documentImageFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelResidenceChangeRequest(
    int requestId,
  ) async {
    final response = await dio.post(
      '/api/feed/profile/me/residence-change/$requestId/cancel',
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

  Future<Map<String, dynamic>> listMyReportedPosts({
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/profile/me/reported-posts',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyReportedStories({
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/profile/me/reported-stories',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> resubmitModeratedPost({
    required int postId,
    required String caption,
    LocalMediaFile? mediaFile,
    bool clearMedia = false,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      if (clearMedia) 'clearMedia': true,
    };
    final response = mediaFile == null
        ? await dio.patch('/api/feed/posts/$postId/resubmit', data: payload)
        : await dio.patch(
            '/api/feed/posts/$postId/resubmit',
            data: FormData.fromMap({
              ...payload,
              'mediaFile': await mediaFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> resubmitModeratedStory({
    required int storyId,
    required String caption,
    LocalMediaFile? mediaFile,
    bool clearMedia = false,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      if (clearMedia) 'clearMedia': true,
    };
    final response = mediaFile == null
        ? await dio.patch('/api/feed/stories/$storyId/resubmit', data: payload)
        : await dio.patch(
            '/api/feed/stories/$storyId/resubmit',
            data: FormData.fromMap({
              ...payload,
              'mediaFile': await mediaFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserFollowers({
    required int userId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/feed/users/$userId/followers',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserFollowing({
    required int userId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/feed/users/$userId/following',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserFriends({
    required int userId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/feed/users/$userId/friends',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserLikedPosts({
    required int userId,
    int limit = 50,
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
      '/api/feed/users/$userId/liked-posts',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listUserCommentedPosts({
    required int userId,
    int limit = 50,
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
      '/api/feed/users/$userId/commented-posts',
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
      Map<String, dynamic>? reelStyle,
      String? audienceScopeType,
      String? audienceScopeCode,
      String? linkTargetType,
    int? linkMerchantId,
    int? linkProductId,
    int? linkOfferId,
    int? linkCouponId,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      'postKind': postKind,
      'merchantId': merchantId,
        'reviewRating': reviewRating,
        'reelStyle': reelStyle,
        'audienceScopeType': audienceScopeType,
        'audienceScopeCode': audienceScopeCode,
      'linkTargetType': linkTargetType,
      'linkMerchantId': linkMerchantId,
      'linkProductId': linkProductId,
      'linkOfferId': linkOfferId,
      'linkCouponId': linkCouponId,
    }..removeWhere((_, value) => value == null);

    final response = mediaFile == null
        ? await dio.post('/api/feed/posts', data: payload)
        : await dio.post(
            '/api/feed/posts',
              data: FormData.fromMap({
                ...payload,
                if (reelStyle != null) 'reelStyle': jsonEncode(reelStyle),
                'mediaFile': await mediaFile.toMultipartFile(),
              }),
            );

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createStory({
    required String caption,
    LocalMediaFile? mediaFile,
    Map<String, dynamic>? storyStyle,
    String? linkTargetType,
    int? linkMerchantId,
    int? linkProductId,
    int? linkOfferId,
    int? linkCouponId,
  }) async {
    final payload = <String, dynamic>{
      'caption': caption,
      'storyStyle': storyStyle,
      'linkTargetType': linkTargetType,
      'linkMerchantId': linkMerchantId,
      'linkProductId': linkProductId,
      'linkOfferId': linkOfferId,
      'linkCouponId': linkCouponId,
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

  Future<Map<String, dynamic>> archiveStory(int storyId) async {
    final response = await dio.post('/api/feed/stories/$storyId/archive');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> restoreStory(int storyId) async {
    final response = await dio.post('/api/feed/stories/$storyId/restore');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> toggleLike(int postId) async {
    final response = await dio.post('/api/feed/posts/$postId/like');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> archivePost(int postId) async {
    final response = await dio.post('/api/feed/posts/$postId/archive');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> restorePost(int postId) async {
    final response = await dio.post('/api/feed/posts/$postId/restore');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deletePost(int postId) async {
    final response = await dio.delete('/api/feed/posts/$postId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listPostLikers({
    required int postId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/feed/posts/$postId/likes',
      queryParameters: {'limit': limit},
    );
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

  Future<Map<String, dynamic>> addCommentReply({
    required int postId,
    required int parentCommentId,
    required String body,
  }) async {
    final response = await dio.post(
      '/api/feed/posts/$postId/comments',
      data: {'body': body, 'parentCommentId': parentCommentId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateComment({
    required int postId,
    required int commentId,
    required String body,
  }) async {
    final response = await dio.patch(
      '/api/feed/posts/$postId/comments/$commentId',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deleteComment({
    required int postId,
    required int commentId,
  }) async {
    final response = await dio.delete(
      '/api/feed/posts/$postId/comments/$commentId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> toggleCommentLike({
    required int postId,
    required int commentId,
  }) async {
    final response = await dio.post(
      '/api/feed/posts/$postId/comments/$commentId/like',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reportPost({
    required int postId,
    required String reason,
    String? details,
  }) async {
    final response = await dio.post(
      '/api/feed/posts/$postId/report',
      data: {
        'reason': reason,
        if ((details ?? '').trim().isNotEmpty) 'details': details,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reportUser({
    required int userId,
    required String reason,
    String? details,
  }) async {
    final response = await dio.post(
      '/api/feed/users/$userId/report',
      data: {
        'reason': reason,
        if ((details ?? '').trim().isNotEmpty) 'details': details,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> toggleStoryLike(int storyId) async {
    final response = await dio.post('/api/feed/stories/$storyId/like');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listStoryComments(
    int storyId, {
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/stories/$storyId/comments',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addStoryComment(int storyId, String body) async {
    final response = await dio.post(
      '/api/feed/stories/$storyId/comments',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reportStory({
    required int storyId,
    required String reason,
    String? details,
  }) async {
    final response = await dio.post(
      '/api/feed/stories/$storyId/report',
      data: {
        'reason': reason,
        if ((details ?? '').trim().isNotEmpty) 'details': details,
      },
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

  Future<Map<String, dynamic>> searchUsers({
    String search = '',
    int limit = 60,
  }) async {
    final response = await dio.get(
      '/api/feed/users/search',
      queryParameters: {'search': search, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listThreads() async {
    final response = await dio.get('/api/feed/chats/threads');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listChatRequests() async {
    final response = await dio.get('/api/feed/chats/requests');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getMyChatQualityReviewConsent() async {
    final response = await dio.get(
      '/api/feed/chats/privacy/quality-review-consent',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setMyChatQualityReviewConsent(
    bool enabled,
  ) async {
    final response = await dio.patch(
      '/api/feed/chats/privacy/quality-review-consent',
      data: {'enabled': enabled},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createThread(
    int userId, {
    String kind = 'private',
    String? contextType,
    int? contextId,
  }) async {
    final payload = <String, dynamic>{
      'userId': userId,
      'kind': kind.trim().isEmpty ? 'private' : kind.trim(),
    };
    if ((contextType ?? '').trim().isNotEmpty && contextId != null) {
      payload['contextType'] = contextType!.trim();
      payload['contextId'] = contextId;
      payload['context'] = <String, dynamic>{
        'type': contextType.trim(),
        'id': contextId,
      };
    }
    final response = await dio.post('/api/feed/chats/threads', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createGroupThread({
    required String title,
    required List<int> memberIds,
    String? imageUrl,
  }) async {
    final payload = <String, dynamic>{
      'kind': 'group',
      'title': title.trim(),
      'memberIds': memberIds,
    };
    if ((imageUrl ?? '').trim().isNotEmpty) {
      payload['imageUrl'] = imageUrl!.trim();
    }
    final response = await dio.post('/api/feed/chats/threads', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getGroupThreadDetails(int threadId) async {
    final response = await dio.get('/api/feed/chats/threads/$threadId/group');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateGroupThread(
    int threadId, {
    required String title,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/group',
      data: {'title': title.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addGroupThreadMembers(
    int threadId, {
    required List<int> memberIds,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/group/members',
      data: {'memberIds': memberIds},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> removeGroupThreadMember(
    int threadId, {
    required int memberUserId,
  }) async {
    final response = await dio.delete(
      '/api/feed/chats/threads/$threadId/group/members/$memberUserId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateGroupThreadMemberRole(
    int threadId, {
    required int memberUserId,
    required String memberRole,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/group/members/$memberUserId/role',
      data: {'memberRole': memberRole.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> leaveGroupThread(int threadId) async {
    final response = await dio.post('/api/feed/chats/threads/$threadId/group/leave');
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

  Future<Map<String, dynamic>> searchThreadMessages(
    int threadId, {
    required String search,
    int limit = 20,
    int? beforeId,
  }) async {
    final query =
        <String, dynamic>{
          'search': search.trim(),
          'limit': limit,
          'beforeId': beforeId,
        }..removeWhere((_, value) {
          if (value == null) return true;
          if (value is String && value.trim().isEmpty) return true;
          return false;
        });

    final response = await dio.get(
      '/api/feed/chats/threads/$threadId/messages/search',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendThreadMessage(
    int threadId,
    String body, {
    int? replyToMessageId,
    LocalMediaFile? attachmentFile,
    int? attachmentDurationMs,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
  }) async {
    final payload = <String, dynamic>{'body': body};
    if (replyToMessageId != null) {
      payload['replyToMessageId'] = replyToMessageId;
    }
    if (attachmentDurationMs != null && attachmentDurationMs > 0) {
      payload['attachmentDurationMs'] = attachmentDurationMs;
    }
    if ((sharedEntityType ?? '').trim().isNotEmpty && sharedEntityId != null) {
      payload['sharedEntityType'] = sharedEntityType!.trim();
      payload['sharedEntityId'] = sharedEntityId;
      if (sharedSnapshot != null && sharedSnapshot.isNotEmpty) {
        payload['sharedEntity'] = <String, dynamic>{
          'type': sharedEntityType.trim(),
          'id': sharedEntityId,
          'snapshot': sharedSnapshot,
        };
      }
    }

    final response = attachmentFile == null
        ? await dio.post(
            '/api/feed/chats/threads/$threadId/messages',
            data: payload,
          )
        : await dio.post(
            '/api/feed/chats/threads/$threadId/messages',
            data: FormData.fromMap({
              ...payload,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> scheduleThreadMessage(
    int threadId,
    String body, {
    required DateTime scheduledFor,
    int? replyToMessageId,
    LocalMediaFile? attachmentFile,
    int? attachmentDurationMs,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
  }) async {
    final payload = <String, dynamic>{
      'body': body,
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    };
    if (replyToMessageId != null) {
      payload['replyToMessageId'] = replyToMessageId;
    }
    if (attachmentDurationMs != null && attachmentDurationMs > 0) {
      payload['attachmentDurationMs'] = attachmentDurationMs;
    }
    if ((sharedEntityType ?? '').trim().isNotEmpty && sharedEntityId != null) {
      payload['sharedEntityType'] = sharedEntityType!.trim();
      payload['sharedEntityId'] = sharedEntityId;
      if (sharedSnapshot != null && sharedSnapshot.isNotEmpty) {
        payload['sharedEntity'] = <String, dynamic>{
          'type': sharedEntityType.trim(),
          'id': sharedEntityId,
          'snapshot': sharedSnapshot,
        };
      }
    }

    final response = attachmentFile == null
        ? await dio.post(
            '/api/feed/chats/threads/$threadId/messages/scheduled',
            data: payload,
          )
        : await dio.post(
            '/api/feed/chats/threads/$threadId/messages/scheduled',
            data: FormData.fromMap({
              ...payload,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listScheduledThreadMessages(
    int threadId, {
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/feed/chats/threads/$threadId/messages/scheduled',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelScheduledThreadMessage({
    required int threadId,
    required int scheduledMessageId,
  }) async {
    final response = await dio.delete(
      '/api/feed/chats/threads/$threadId/messages/scheduled/$scheduledMessageId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateThreadMessage({
    required int threadId,
    required int messageId,
    required String body,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/messages/$messageId',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> translateThreadMessage({
    required int threadId,
    required int messageId,
    required String targetLanguage,
    bool refresh = false,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/messages/$messageId/translate',
      data: {
        'targetLanguage': targetLanguage.trim().toLowerCase(),
        'refresh': refresh,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deleteThreadMessage({
    required int threadId,
    required int messageId,
  }) async {
    final response = await dio.delete(
      '/api/feed/chats/threads/$threadId/messages/$messageId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAdminMonitoredThreads({
    String search = '',
    int limit = 80,
    String kind = 'all',
  }) async {
    final response = await dio.get(
      '/api/feed/admin/chats/threads',
      queryParameters: {
        'search': search.trim(),
        'limit': limit,
        'kind': kind.trim().isEmpty ? 'all' : kind.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAdminMonitoredThreadMessages(
    int threadId, {
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/admin/chats/threads/$threadId/messages',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAdminMonitoredCommunityMessages({
    required String scopeType,
    required String scopeCode,
    int limit = 60,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/admin/chats/community/$scopeType/$scopeCode/messages',
      queryParameters: query,
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

  Future<Map<String, dynamic>> acceptChatRequest(int threadId) async {
    final response = await dio.post(
      '/api/feed/chats/requests/$threadId/accept',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectChatRequest(int threadId) async {
    final response = await dio.post(
      '/api/feed/chats/requests/$threadId/reject',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> blockChatRequest(int threadId) async {
    final response = await dio.post('/api/feed/chats/requests/$threadId/block');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setThreadTheme({
    required int threadId,
    required String themeKey,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/theme',
      data: {'themeKey': themeKey.trim().toLowerCase()},
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

  Future<Map<String, dynamic>> listCommunityScopes() async {
    final response = await dio.get('/api/feed/communities/scopes/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityFeed({
    required String scopeType,
    required String scopeCode,
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
      '/api/feed/communities/$scopeType/$scopeCode/feed',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityAnnouncements({
    required String scopeType,
    required String scopeCode,
    int limit = 40,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/announcements',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createCommunityAnnouncement({
    required String scopeType,
    required String scopeCode,
    required String title,
    required String body,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/announcements',
      data: {'title': title, 'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityChatMessages({
    required String scopeType,
    required String scopeCode,
    int limit = 60,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'beforeId': beforeId}
      ..removeWhere((_, value) => value == null);
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/chat/messages',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> searchCommunityChatMessages({
    required String scopeType,
    required String scopeCode,
    required String search,
    int limit = 20,
    int? beforeId,
  }) async {
    final query =
        <String, dynamic>{
          'search': search.trim(),
          'limit': limit,
          'beforeId': beforeId,
        }..removeWhere((_, value) {
          if (value == null) return true;
          if (value is String && value.trim().isEmpty) return true;
          return false;
        });
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/chat/messages/search',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendCommunityChatMessage({
    required String scopeType,
    required String scopeCode,
    required String body,
    int? replyToMessageId,
    LocalMediaFile? attachmentFile,
    int? attachmentDurationMs,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
  }) async {
    final payload = <String, dynamic>{'body': body};
    if (replyToMessageId != null) {
      payload['replyToMessageId'] = replyToMessageId;
    }
    if (attachmentDurationMs != null && attachmentDurationMs > 0) {
      payload['attachmentDurationMs'] = attachmentDurationMs;
    }
    if ((sharedEntityType ?? '').trim().isNotEmpty && sharedEntityId != null) {
      payload['sharedEntityType'] = sharedEntityType!.trim();
      payload['sharedEntityId'] = sharedEntityId;
      if (sharedSnapshot != null && sharedSnapshot.isNotEmpty) {
        payload['sharedEntity'] = <String, dynamic>{
          'type': sharedEntityType.trim(),
          'id': sharedEntityId,
          'snapshot': sharedSnapshot,
        };
      }
    }

    final response = attachmentFile == null
        ? await dio.post(
            '/api/feed/communities/$scopeType/$scopeCode/chat/messages',
            data: payload,
          )
        : await dio.post(
            '/api/feed/communities/$scopeType/$scopeCode/chat/messages',
            data: FormData.fromMap({
              ...payload,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> emitCommunityChatTyping({
    required String scopeType,
    required String scopeCode,
    required bool typing,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/chat/typing',
      data: {'typing': typing},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateCommunityChatMessage({
    required String scopeType,
    required String scopeCode,
    required int messageId,
    required String body,
  }) async {
    final response = await dio.patch(
      '/api/feed/communities/$scopeType/$scopeCode/chat/messages/$messageId',
      data: {'body': body},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deleteCommunityChatMessage({
    required String scopeType,
    required String scopeCode,
    required int messageId,
  }) async {
    final response = await dio.delete(
      '/api/feed/communities/$scopeType/$scopeCode/chat/messages/$messageId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> toggleCommunityChatMessageReaction({
    required String scopeType,
    required String scopeCode,
    required int messageId,
    required String reaction,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/chat/messages/$messageId/reaction',
      data: {'reaction': reaction},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setCommunityChatLock({
    required String scopeType,
    required String scopeCode,
    required bool locked,
  }) async {
    final response = await dio.patch(
      '/api/feed/communities/$scopeType/$scopeCode/chat/lock',
      data: {'locked': locked},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> banCommunityChatUser({
    required String scopeType,
    required String scopeCode,
    required int userId,
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/chat/ban',
      data: {
        'userId': userId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> unbanCommunityChatUser({
    required String scopeType,
    required String scopeCode,
    required int userId,
  }) async {
    final response = await dio.delete(
      '/api/feed/communities/$scopeType/$scopeCode/chat/ban/$userId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> removeCommunityMember({
    required String scopeType,
    required String scopeCode,
    required int userId,
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/members/remove',
      data: {
        'userId': userId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> restoreCommunityMember({
    required String scopeType,
    required String scopeCode,
    required int userId,
  }) async {
    final response = await dio.delete(
      '/api/feed/communities/$scopeType/$scopeCode/members/remove/$userId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityChatUsers({
    required String scopeType,
    required String scopeCode,
    String search = '',
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/chat/users',
      queryParameters: {'search': search.trim(), 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityBills({
    required String scopeType,
    required String scopeCode,
    String? category,
    int limit = 60,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{
      'category': category?.trim(),
      'limit': limit,
      'beforeId': beforeId,
    }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty);
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/bills',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createCommunityBill({
    required String scopeType,
    required String scopeCode,
    required String category,
    required String title,
    required String apartment,
    double? amount,
    String? dueDate,
    String? details,
    LocalMediaFile? attachmentFile,
  }) async {
    final payload = <String, dynamic>{
      'category': category,
      'title': title,
      'apartment': apartment.trim().toUpperCase(),
      'amount': amount,
      'dueDate': dueDate?.trim(),
      'details': details?.trim(),
    }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty);

    final response = attachmentFile == null
        ? await dio.post(
            '/api/feed/communities/$scopeType/$scopeCode/bills',
            data: payload,
          )
        : await dio.post(
            '/api/feed/communities/$scopeType/$scopeCode/bills',
            data: FormData.fromMap({
              ...payload,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listCommunityManagers({
    required String scopeType,
    required String scopeCode,
  }) async {
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/managers',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> searchCommunityUsersForManagers({
    required String scopeType,
    required String scopeCode,
    String search = '',
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/feed/communities/$scopeType/$scopeCode/users/search',
      queryParameters: {'search': search, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> assignCommunityManager({
    required String scopeType,
    required String scopeCode,
    required int managerUserId,
  }) async {
    final response = await dio.post(
      '/api/feed/communities/$scopeType/$scopeCode/managers',
      data: {'managerUserId': managerUserId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> revokeCommunityManager({
    required String scopeType,
    required String scopeCode,
    required int userId,
  }) async {
    final response = await dio.delete(
      '/api/feed/communities/$scopeType/$scopeCode/managers/$userId',
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

  Future<Map<String, dynamic>> listExplore({int limit = 18}) async {
    final response = await dio.get(
      '/api/feed/explore',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listTrending({
    int limit = 16,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/feed/trending',
      queryParameters: <String, dynamic>{'limit': limit, 'beforeId': beforeId}
        ..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listExploreReels({
    int limit = 14,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/feed/reels/explore',
      queryParameters: <String, dynamic>{'limit': limit, 'beforeId': beforeId}
        ..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listSuggestedPeople({int limit = 12}) async {
    final response = await dio.get(
      '/api/feed/users/suggested',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> searchSocial({
    required String search,
    String tab = 'all',
    int limit = 12,
  }) async {
    final response = await dio.get(
      '/api/feed/search',
      queryParameters: {'search': search, 'tab': tab, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listTrendingHashtags({int limit = 12}) async {
    final response = await dio.get(
      '/api/feed/hashtags/trending',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listHashtagPosts({
    required String tag,
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/feed/hashtags/${Uri.encodeComponent(tag)}',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMentionSuggestions({
    required String search,
    int limit = 8,
  }) async {
    final response = await dio.get(
      '/api/feed/mentions/users',
      queryParameters: {'search': search, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listHashtagSuggestions({
    required String search,
    int limit = 8,
  }) async {
    final response = await dio.get(
      '/api/feed/hashtags/suggest',
      queryParameters: {'query': search, 'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listShareRecipients({String search = ''}) async {
    final response = await dio.get(
      '/api/feed/share/recipients',
      queryParameters: {'search': search.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> checkUsernameAvailability(
    String username,
  ) async {
    final response = await dio.get(
      '/api/feed/profile/me/username/check',
      queryParameters: {'username': username.trim().toLowerCase()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMyUsername(String username) async {
    final response = await dio.patch(
      '/api/feed/profile/me/username',
      data: {'username': username.trim().toLowerCase()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listSaved({
    String? entityType,
    int? collectionId,
    int limit = 24,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/feed/saved',
      queryParameters: <String, dynamic>{
        'entityType': entityType,
        'collectionId': collectionId,
        'limit': limit,
        'beforeId': beforeId,
      }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listSavedCollections() async {
    final response = await dio.get('/api/feed/saved/collections');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createSavedCollection({
    required String title,
    String? description,
    String? systemKey,
  }) async {
    final response = await dio.post(
      '/api/feed/saved/collections',
      data: <String, dynamic>{
        'title': title,
        'description': description,
        'systemKey': systemKey,
      }..removeWhere((_, value) => value == null || '$value'.trim().isEmpty),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateSavedCollection({
    required int collectionId,
    required String title,
    String? description,
  }) async {
    final response = await dio.patch(
      '/api/feed/saved/collections/$collectionId',
      data: <String, dynamic>{'title': title, 'description': description}
        ..removeWhere((_, value) => value == null || '$value'.trim().isEmpty),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteSavedCollection(int collectionId) async {
    await dio.delete('/api/feed/saved/collections/$collectionId');
  }

  Future<Map<String, dynamic>> toggleSaved({
    required String entityType,
    required int entityId,
    List<int> collectionIds = const <int>[],
  }) async {
    final response = await dio.post(
      '/api/feed/saved/toggle',
      data: {
        'entityType': entityType,
        'entityId': entityId,
        if (collectionIds.isNotEmpty) 'collectionIds': collectionIds,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProfileInsights(int userId) async {
    final response = await dio.get('/api/feed/profiles/$userId/insights');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listProfileReels({
    required int userId,
    int limit = 20,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/feed/profiles/$userId/reels',
      queryParameters: <String, dynamic>{'limit': limit, 'beforeId': beforeId}
        ..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listProfileTagged({
    required int userId,
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/feed/profiles/$userId/tagged',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createReel({
    required String caption,
    required LocalMediaFile mediaFile,
    String? audienceScopeType,
    String? audienceScopeCode,
    String? linkTargetType,
    int? linkMerchantId,
    int? linkProductId,
    int? linkOfferId,
    int? linkCouponId,
  }) async {
    final response = await dio.post(
      '/api/feed/reels',
      data: FormData.fromMap(
        {
          'caption': caption,
          'postKind': 'reel',
          'audienceScopeType': audienceScopeType,
          'audienceScopeCode': audienceScopeCode,
          'linkTargetType': linkTargetType,
          'linkMerchantId': linkMerchantId,
          'linkProductId': linkProductId,
          'linkOfferId': linkOfferId,
          'linkCouponId': linkCouponId,
          'mediaFile': await mediaFile.toMultipartFile(),
        }..removeWhere((_, value) => value == null),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> recordReelView({
    required int reelId,
    int? watchDurationMs,
    double? completionRate,
    bool? completed,
    int? replayCount,
    String? context,
  }) async {
    final response = await dio.post(
      '/api/feed/reels/$reelId/view',
      data: <String, dynamic>{
        'watchDurationMs': watchDurationMs,
        'completionRate': completionRate,
        'completed': completed,
        'replayCount': replayCount,
        'context': context,
      }..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getReelById(int reelId) async {
    final response = await dio.get('/api/feed/reels/$reelId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listThreadMedia({
    required int threadId,
    int limit = 40,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/feed/chats/threads/$threadId/media',
      queryParameters: <String, dynamic>{'limit': limit, 'beforeId': beforeId}
        ..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> emitThreadTyping({
    required int threadId,
    required bool typing,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/typing',
      data: {'typing': typing},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setThreadMute({
    required int threadId,
    required bool enabled,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/mute',
      data: {'enabled': enabled},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setThreadPinned({
    required int threadId,
    required bool enabled,
  }) async {
    final response = await dio.patch(
      '/api/feed/chats/threads/$threadId/pin',
      data: {'enabled': enabled},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> pinThreadMessage({
    required int threadId,
    required int messageId,
  }) async {
    final response = await dio.post(
      '/api/feed/chats/threads/$threadId/messages/$messageId/pin',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> unpinThreadMessage({
    required int threadId,
    required int messageId,
  }) async {
    final response = await dio.delete(
      '/api/feed/chats/threads/$threadId/messages/$messageId/pin',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> markThreadRead({required int threadId}) async {
    final response = await dio.patch('/api/feed/chats/threads/$threadId/read');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
