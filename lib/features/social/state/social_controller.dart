import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/social_api.dart';
import '../data/social_stream_upload_service.dart';
import '../models/social_models.dart';

final socialApiProvider = Provider<SocialApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return SocialApi(dio);
});

const Map<String, String> _socialApiMessages = {
  'CONTENT_NOT_ALLOWED':
      'هذا المحتوى غير مسموح. يرجى تجنب العنف أو الإساءة أو السياسة.',
  'MEDIA_REQUIRED': 'يرجى اختيار صورة أو فيديو قبل النشر.',
  'EMPTY_POST': 'اكتب نصًا أو أضف وسائط قبل النشر.',
  'MERCHANT_REVIEW_INCOMPLETE': 'يرجى اختيار المتجر والتقييم قبل نشر المراجعة.',
  'POST_NOT_FOUND': 'المنشور غير موجود أو تمت إزالته.',
  'THREAD_NOT_FOUND': 'المحادثة غير متاحة.',
  'THREAD_SELF_NOT_ALLOWED': 'لا يمكنك إنشاء محادثة مع نفسك.',
  'RELATION_REQUIRED': 'قبل المراسلة يجب قبول طلب المتابعة بين الطرفين.',
  'RELATION_REQUEST_NOT_FOUND': 'طلب المتابعة غير موجود.',
  'RELATION_ACCEPT_NOT_ALLOWED': 'لا يمكن قبول هذا الطلب حاليًا.',
  'RELATION_REJECT_NOT_ALLOWED': 'لا يمكن رفض هذا الطلب حاليًا.',
  'RELATION_CANCEL_NOT_ALLOWED': 'لا يمكن إلغاء هذا الطلب حاليًا.',
  'RELATION_BLOCKED': 'لا يمكن إتمام العملية بسبب إعدادات الخصوصية.',
  'EMPTY_STORY': 'أضف نصًا أو صورة أو فيديو قبل نشر الستوري.',
  'STORY_NOT_FOUND': 'الستوري غير متاحة حاليًا.',
  'INVALID_MEDIA_TYPE':
      'نوع الملف غير مدعوم. استخدم JPG أو PNG أو WEBP أو MP4.',
};

/// حالة المجتمع المركزية: القصص، المنشورات، threads، ونوع الفلترة النشط.
class SocialState {
  final bool loadingStories;
  final bool creatingStory;
  final List<SocialStoryGroup> stories;
  final bool loadingPosts;
  final bool loadingMorePosts;
  final bool creatingPost;
  final List<SocialPost> posts;
  final int? nextPostsCursor;
  final bool loadingThreads;
  final List<SocialChatThread> threads;
  final String? activeKind;
  final String? error;

  const SocialState({
    this.loadingStories = false,
    this.creatingStory = false,
    this.stories = const [],
    this.loadingPosts = false,
    this.loadingMorePosts = false,
    this.creatingPost = false,
    this.posts = const [],
    this.nextPostsCursor,
    this.loadingThreads = false,
    this.threads = const [],
    this.activeKind,
    this.error,
  });

  SocialState copyWith({
    bool? loadingStories,
    bool? creatingStory,
    List<SocialStoryGroup>? stories,
    bool? loadingPosts,
    bool? loadingMorePosts,
    bool? creatingPost,
    List<SocialPost>? posts,
    int? nextPostsCursor,
    bool nextPostsCursorTouched = false,
    bool? loadingThreads,
    List<SocialChatThread>? threads,
    String? activeKind,
    bool activeKindTouched = false,
    String? error,
  }) {
    return SocialState(
      loadingStories: loadingStories ?? this.loadingStories,
      creatingStory: creatingStory ?? this.creatingStory,
      stories: stories ?? this.stories,
      loadingPosts: loadingPosts ?? this.loadingPosts,
      loadingMorePosts: loadingMorePosts ?? this.loadingMorePosts,
      creatingPost: creatingPost ?? this.creatingPost,
      posts: posts ?? this.posts,
      nextPostsCursor: nextPostsCursorTouched
          ? nextPostsCursor
          : this.nextPostsCursor,
      loadingThreads: loadingThreads ?? this.loadingThreads,
      threads: threads ?? this.threads,
      activeKind: activeKindTouched ? activeKind : this.activeKind,
      error: error,
    );
  }
}

final socialControllerProvider =
    StateNotifierProvider<SocialController, SocialState>(
      (ref) => SocialController(ref),
    );

/// المتحكم المركزي لوحدة المجتمع في الواجهة.
///
/// Maintenance notes:
/// - عند desync بين القصص والمنشورات أو عند paging غير صحيح، ابدأ من هذا
///   الملف ثم راجع `SocialApi`.
class SocialController extends StateNotifier<SocialState> {
  final Ref ref;
  bool _disposed = false;

  SocialController(this.ref) : super(const SocialState());

  void _safeSetState(SocialState next) {
    if (_disposed) return;
    state = next;
  }

  bool _hasVerifiedSession() {
    final auth = ref.read(authControllerProvider);
    return auth.isAuthed && auth.user != null;
  }

  bool _isAuthFailure(Object error) {
    return error is DioException && isAuthDioError(error);
  }

  Future<int?> _uploadStreamVideoIfNeeded({
    required String sourceType,
    required LocalMediaFile? mediaFile,
    required String title,
    bool waitForReady = true,
  }) async {
    if (mediaFile == null || !mediaFile.isVideo) return null;
    final uploader = SocialStreamUploadService(ref.read(socialApiProvider));
    final asset = await uploader.uploadVideoAndWaitReady(
      mediaFile: mediaFile,
      sourceType: sourceType,
      title: title,
      // Stories publish while PROCESSING — do not block on encoding.
      waitForReady: waitForReady,
    );
    return asset.id;
  }

  /// يحمل القصص والمنشورات والـ threads معاً عند فتح التجربة الاجتماعية.
  Future<void> bootstrap() async {
    if (_hasVerifiedSession()) {
      await Future.wait([
        loadStories(),
        loadPosts(refresh: true),
        loadThreads(),
      ]);
      return;
    }
    await Future.wait([loadStories(), loadPosts(refresh: true)]);
  }

  /// يبدل نوع المحتوى النشط ويعيد تحميل feed من البداية.
  Future<void> setActiveKind(String? kind) async {
    final normalized = kind == null || kind.trim().isEmpty ? null : kind.trim();
    if (normalized == state.activeKind && state.posts.isNotEmpty) return;
    _safeSetState(
      state.copyWith(
        activeKind: normalized,
        activeKindTouched: true,
        nextPostsCursor: null,
        nextPostsCursorTouched: true,
      ),
    );
    await loadPosts(refresh: true, kind: normalized);
  }

  /// يحمل صفحة منشورات مع دعم refresh وload-more.
  Future<void> loadPosts({
    bool refresh = false,
    String? kind,
    bool silent = false,
  }) async {
    final effectiveKind = kind ?? state.activeKind;
    final loadingMore = !refresh && state.posts.isNotEmpty;
    if (!silent) {
      _safeSetState(
        state.copyWith(
          loadingPosts: refresh,
          loadingMorePosts: loadingMore,
          error: null,
        ),
      );
    }

    try {
      final response = await ref
          .read(socialApiProvider)
          .listPosts(
            limit: 20,
            beforeId: loadingMore ? state.nextPostsCursor : null,
            kind: effectiveKind,
          );
      final rawPosts = List<dynamic>.from(
        response['posts'] as List? ?? const [],
      );
      final parsed = rawPosts
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);

      final merged = loadingMore
          ? _mergePosts(state.posts, parsed)
          : _mergePosts(const <SocialPost>[], parsed);
      _safeSetState(
        state.copyWith(
          loadingPosts: silent ? state.loadingPosts : false,
          loadingMorePosts: silent ? state.loadingMorePosts : false,
          posts: merged,
          activeKind: effectiveKind,
          activeKindTouched: true,
          nextPostsCursor: _parseInt(response['nextCursor']),
          nextPostsCursorTouched: true,
        ),
      );
    } on DioException catch (e) {
      if (_isAuthFailure(e)) {
        _safeSetState(
          state.copyWith(
            loadingPosts: false,
            loadingMorePosts: false,
            error: null,
          ),
        );
        return;
      }
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingPosts: false,
          loadingMorePosts: false,
          error: mapDioError(
            e,
            fallback: 'تعذر تحميل منشورات مسلكي.',
            customMessages: _socialApiMessages,
            appendRequestId: true,
          ),
        ),
      );
    } catch (e) {
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingPosts: false,
          loadingMorePosts: false,
          error: mapAnyError(e, fallback: 'تعذر تحميل المنشورات.'),
        ),
      );
    }
  }

  Future<void> loadMorePosts() async {
    if (state.loadingPosts || state.loadingMorePosts) return;
    if (state.nextPostsCursor == null) return;
    await loadPosts(refresh: false, silent: false);
  }

  /// يحمل القصص النشطة الظاهرة للمستخدم.
  Future<void> loadStories({bool silent = false}) async {
    if (!silent) {
      _safeSetState(state.copyWith(loadingStories: true, error: null));
    }
    try {
      final out = await ref
          .read(socialApiProvider)
          .listStories(limitUsers: 32, maxPerUser: 10);
      final raw = List<dynamic>.from(out['stories'] as List? ?? const []);
      final stories = raw
          .map(
            (e) =>
                SocialStoryGroup.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
      _safeSetState(
        state.copyWith(
          loadingStories: silent ? state.loadingStories : false,
          stories: stories,
        ),
      );
    } on DioException catch (e) {
      if (_isAuthFailure(e)) {
        _safeSetState(state.copyWith(loadingStories: false, error: null));
        return;
      }
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingStories: false,
          error: mapDioError(
            e,
            fallback: 'تعذر تحميل الستوري.',
            customMessages: _socialApiMessages,
            appendRequestId: true,
          ),
        ),
      );
    } catch (e) {
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingStories: false,
          error: mapAnyError(e, fallback: 'تعذر تحميل الستوري.'),
        ),
      );
    }
  }

  Future<void> createStory({
    required String caption,
    int? mediaAssetId,
    LocalMediaFile? mediaFile,
    Map<String, dynamic>? storyStyle,
    String? audienceScopeType,
    String? audienceScopeCode,
  }) async {
    _safeSetState(state.copyWith(creatingStory: true, error: null));
    try {
      final api = ref.read(socialApiProvider);
      final resolvedAssetId =
          mediaAssetId ??
          await _uploadStreamVideoIfNeeded(
            sourceType: 'story',
            mediaFile: mediaFile,
            title: caption.isNotEmpty ? caption : 'story',
            // A Story is published as soon as the video upload is accepted; it
            // shows a PROCESSING state and is reconciled to READY afterwards.
            waitForReady: false,
          );
      final response = await api.createStory(
        caption: caption,
        mediaAssetId: resolvedAssetId,
        mediaFile: resolvedAssetId != null ? null : mediaFile,
        storyStyle: storyStyle,
        audienceScopeType: audienceScopeType,
        audienceScopeCode: audienceScopeCode,
      );
      _safeSetState(state.copyWith(creatingStory: false));

      // §1: insert the authoritative created Story directly into the current
      // user's group — no full loadStories()/loadPosts() reload.
      final storyJson = response['story'];
      if (storyJson is Map) {
        final story = SocialStory.fromJson(
          Map<String, dynamic>.from(storyJson),
        );
        _insertOrReplaceOwnStory(story);
        // §2: if the video is still PROCESSING, reconcile only this asset.
        final asset = story.asset;
        if (asset?.id != null && asset?.isReady != true) {
          unawaited(_reconcileStoryAsset(asset!.id!));
        }
      } else {
        // Fallback only when the backend did not echo the story.
        await loadStories(silent: true);
      }
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          creatingStory: false,
          error: mapDioError(
            e,
            fallback: 'تعذر نشر الستوري.',
            customMessages: _socialApiMessages,
            appendRequestId: true,
          ),
        ),
      );
    } catch (e) {
      _safeSetState(
        state.copyWith(
          creatingStory: false,
          error: mapAnyError(e, fallback: 'تعذر نشر الستوري.'),
        ),
      );
    }
  }

  final Set<int> _reconcilingAssetIds = {};

  /// Inserts/updates ONLY the current user's story group (§1). Dedupes by story
  /// id and media asset id; preserves every other group; moves the current
  /// user's group to the front.
  void _insertOrReplaceOwnStory(SocialStory story) {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final groups = List<SocialStoryGroup>.of(state.stories);
    final idx = groups.indexWhere((g) => g.userId == user.id);
    if (idx >= 0) {
      final g = groups[idx];
      final stories = List<SocialStory>.of(g.stories)
        ..removeWhere(
          (s) =>
              s.id == story.id ||
              (story.asset?.id != null && s.asset?.id == story.asset?.id),
        );
      stories.insert(0, story);
      groups.removeAt(idx);
      groups.insert(
        0,
        SocialStoryGroup(
          userId: g.userId,
          author: g.author,
          latestAt: story.createdAt ?? g.latestAt,
          hasUnviewed: g.hasUnviewed,
          stories: stories,
        ),
      );
    } else {
      groups.insert(
        0,
        SocialStoryGroup(
          userId: user.id,
          author: SocialAuthor(
            id: user.id,
            username: null,
            fullName: user.fullName,
            imageUrl: user.imageUrl,
            phone: user.phone,
            role: user.role,
            badges: const [],
            isResidentVerified: false,
            isMerchantVerified: false,
            isPremiumCreator: false,
          ),
          latestAt: story.createdAt,
          hasUnviewed: false,
          stories: [story],
        ),
      );
    }
    _safeSetState(state.copyWith(stories: groups));
  }

  /// §2: bounded, single-flight reconciliation for ONE processing media asset.
  /// Polls only this asset (the backend reconcile worker refreshes it from
  /// Cloudflare) and, when READY, pulls the authoritative story once. Stops on
  /// terminal states, logout/account switch, disposal, or the attempt budget.
  Future<void> _reconcileStoryAsset(int assetId) async {
    if (assetId <= 0 || _reconcilingAssetIds.contains(assetId)) return;
    _reconcilingAssetIds.add(assetId);
    final ownerUserId = ref.read(authControllerProvider).user?.id;
    try {
      const maxAttempts = 20;
      var delay = const Duration(seconds: 3);
      for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
        await Future<void>.delayed(delay);
        if (!mounted) return;
        if (ref.read(authControllerProvider).user?.id != ownerUserId) return;
        SocialMediaAsset? asset;
        try {
          asset = await ref.read(socialApiProvider).getMediaAsset(assetId);
        } catch (_) {
          // transient — keep trying within the budget
        }
        final status = (asset?.processingStatus ?? '').trim().toLowerCase();
        if (asset?.isReady == true || status == 'ready') {
          await loadStories(silent: true);
          return;
        }
        if (status == 'failed' || status == 'rejected' || status == 'deleted') {
          _safeSetState(state.copyWith(error: 'تعذّر تجهيز فيديو الستوري.'));
          return;
        }
        delay = Duration(seconds: (delay.inSeconds + 2).clamp(3, 15));
      }
    } finally {
      _reconcilingAssetIds.remove(assetId);
    }
  }

  Future<void> markStoryViewed(int storyId) async {
    SocialStoryGroup? targetGroup;
    SocialStory? targetStory;
    for (final group in state.stories) {
      for (final story in group.stories) {
        if (story.id == storyId) {
          targetGroup = group;
          targetStory = story;
          break;
        }
      }
      if (targetStory != null) break;
    }
    if (targetStory == null || targetStory.isViewed || targetStory.isMine) {
      return;
    }

    try {
      await ref.read(socialApiProvider).markStoryViewed(storyId);
      final updatedStories = state.stories
          .map((group) {
            if (group.userId != targetGroup!.userId) return group;
            final nextGroupStories = group.stories
                .map((story) {
                  if (story.id != storyId) return story;
                  return SocialStory(
                    id: story.id,
                    userId: story.userId,
                    caption: story.caption,
                    mediaUrl: story.mediaUrl,
                    mediaKind: story.mediaKind,
                    asset: story.asset,
                    style: story.style,
                    archivedAt: story.archivedAt,
                    likesCount: story.likesCount,
                    commentsCount: story.commentsCount,
                    isLiked: story.isLiked,
                    isViewed: true,
                    isMine: story.isMine,
                    createdAt: story.createdAt,
                    expiresAt: story.expiresAt,
                  );
                })
                .toList(growable: false);
            final hasUnviewed = nextGroupStories.any(
              (s) => !s.isViewed && !s.isMine,
            );
            return SocialStoryGroup(
              userId: group.userId,
              author: group.author,
              latestAt: group.latestAt,
              hasUnviewed: hasUnviewed,
              stories: nextGroupStories,
            );
          })
          .toList(growable: false);
      _safeSetState(state.copyWith(stories: updatedStories));
    } catch (_) {
      // Keep UI alive; next refresh will sync.
    }
  }

  Future<void> refreshFeedTick() async {
    await Future.wait([
      loadStories(silent: true),
      loadPosts(refresh: true, silent: true),
    ]);
  }

  Future<SocialPost?> ensurePostVisible(int postId) async {
    SocialPost? existing;
    for (final item in state.posts) {
      if (item.id == postId) {
        existing = item;
        break;
      }
    }
    if (existing != null) return existing;
    try {
      final out = await ref.read(socialApiProvider).getPostById(postId);
      final raw = out['post'];
      if (raw is! Map) return null;
      final post = SocialPost.fromJson(Map<String, dynamic>.from(raw));
      _safeSetState(
        state.copyWith(
          posts: [post, ...state.posts.where((p) => p.id != post.id)],
        ),
      );
      return post;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> createPost({
    required String caption,
    required String postKind,
    int? merchantId,
    int? reviewRating,
    int? mediaAssetId,
    LocalMediaFile? mediaFile,
    List<LocalMediaFile>? mediaFiles,
    Map<String, dynamic>? reelStyle,
    String? audienceScopeType,
    String? audienceScopeCode,
  }) async {
    _safeSetState(state.copyWith(creatingPost: true, error: null));
    try {
      final api = ref.read(socialApiProvider);
      final normalizedKind = postKind.trim().toLowerCase();
      final normalizedMediaFiles = <LocalMediaFile>[
        ...?mediaFiles,
        ...(mediaFile == null
            ? const <LocalMediaFile>[]
            : <LocalMediaFile>[mediaFile]),
      ];
      int? resolvedAssetId = mediaAssetId;
      if (resolvedAssetId == null &&
          normalizedMediaFiles.length == 1 &&
          normalizedMediaFiles.single.isVideo &&
          (normalizedKind == 'reel' || normalizedKind == 'video')) {
        resolvedAssetId = await _uploadStreamVideoIfNeeded(
          sourceType: normalizedKind == 'reel' ? 'reel' : 'post',
          mediaFile: normalizedMediaFiles.single,
          title: caption.isNotEmpty ? caption : normalizedKind,
        );
      }
      final out = await api.createPost(
        caption: caption,
        postKind: postKind,
        merchantId: merchantId,
        reviewRating: reviewRating,
        mediaAssetId: resolvedAssetId,
        mediaFile: resolvedAssetId != null ? null : mediaFile,
        mediaFiles: resolvedAssetId != null ? null : mediaFiles,
        reelStyle: reelStyle,
        audienceScopeType: audienceScopeType,
        audienceScopeCode: audienceScopeCode,
      );
      final postMap = Map<String, dynamic>.from(out['post'] as Map);
      final post = SocialPost.fromJson(postMap);
      _safeSetState(
        state.copyWith(
          creatingPost: false,
          posts: [post, ...state.posts.where((p) => p.id != post.id)],
        ),
      );
      await loadThreads();
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          creatingPost: false,
          error: mapDioError(
            e,
            fallback: 'تعذر نشر المنشور. تحقق من المحتوى وحاول مرة أخرى.',
            customMessages: _socialApiMessages,
            appendRequestId: true,
          ),
        ),
      );
    } catch (e) {
      _safeSetState(
        state.copyWith(
          creatingPost: false,
          error: mapAnyError(e, fallback: 'تعذر نشر المنشور.'),
        ),
      );
    }
  }

  Future<void> toggleLike(SocialPost post) async {
    final previous = post;
    final optimistic = post.copyWith(
      isLiked: !post.isLiked,
      likesCount: (post.likesCount + (post.isLiked ? -1 : 1)).clamp(0, 999999),
    );
    _safeSetState(
      state.copyWith(
        posts: state.posts
            .map((p) => p.id == post.id ? optimistic : p)
            .toList(growable: false),
        error: null,
      ),
    );

    try {
      final out = await ref.read(socialApiProvider).toggleLike(post.id);
      final likesCount = _parseInt(out['likesCount']) ?? optimistic.likesCount;
      final liked = out['liked'] == true;
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map(
                (p) => p.id == post.id
                    ? p.copyWith(isLiked: liked, likesCount: likesCount)
                    : p,
              )
              .toList(growable: false),
        ),
      );
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map((p) => p.id == post.id ? previous : p)
              .toList(growable: false),
          error: mapDioError(
            e,
            fallback: 'تعذر تحديث الإعجاب.',
            customMessages: _socialApiMessages,
          ),
        ),
      );
    } catch (_) {
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map((p) => p.id == post.id ? previous : p)
              .toList(growable: false),
        ),
      );
    }
  }

  Future<void> toggleSave(SocialPost post) async {
    final previous = post;
    final optimisticSaved = !post.isSaved;
    final optimistic = post.copyWith(
      isSaved: optimisticSaved,
      savesCount: (post.savesCount + (post.isSaved ? -1 : 1)).clamp(0, 999999),
    );
    _safeSetState(
      state.copyWith(
        posts: state.posts
            .map((p) => p.id == post.id ? optimistic : p)
            .toList(growable: false),
        error: null,
      ),
    );

    final entityType = post.postKind == 'merchant_review'
        ? 'review'
        : post.postKind == 'reel'
        ? 'reel'
        : 'post';

    try {
      final out = await ref
          .read(socialApiProvider)
          .toggleSaved(entityType: entityType, entityId: post.id);
      final savesCount =
          _parseInt(out['savesCount'] ?? out['saves_count']) ??
          optimistic.savesCount;
      final saved = out['saved'] == true;
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map(
                (p) => p.id == post.id
                    ? p.copyWith(isSaved: saved, savesCount: savesCount)
                    : p,
              )
              .toList(growable: false),
        ),
      );
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map((p) => p.id == post.id ? previous : p)
              .toList(growable: false),
          error: mapDioError(
            e,
            fallback: 'تعذر تحديث المحفوظات.',
            customMessages: _socialApiMessages,
          ),
        ),
      );
    } catch (_) {
      _safeSetState(
        state.copyWith(
          posts: state.posts
              .map((p) => p.id == post.id ? previous : p)
              .toList(growable: false),
        ),
      );
    }
  }

  void patchCommentsCount({required int postId, required int commentsCount}) {
    _safeSetState(
      state.copyWith(
        posts: state.posts
            .map(
              (p) =>
                  p.id == postId ? p.copyWith(commentsCount: commentsCount) : p,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> loadThreads({bool silent = false}) async {
    if (!_hasVerifiedSession()) {
      _safeSetState(state.copyWith(loadingThreads: false, error: null));
      return;
    }
    if (!silent) {
      _safeSetState(state.copyWith(loadingThreads: true, error: null));
    }
    try {
      final out = await ref.read(socialApiProvider).listThreads();
      final raw = List<dynamic>.from(out['threads'] as List? ?? const []);
      final threads = raw
          .map(
            (e) =>
                SocialChatThread.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
      _safeSetState(
        state.copyWith(
          loadingThreads: silent ? state.loadingThreads : false,
          threads: threads,
        ),
      );
    } on DioException catch (e) {
      if (_isAuthFailure(e)) {
        _safeSetState(state.copyWith(loadingThreads: false, error: null));
        return;
      }
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingThreads: false,
          error: mapDioError(
            e,
            fallback: 'تعذر تحميل المحادثات.',
            customMessages: _socialApiMessages,
          ),
        ),
      );
    } catch (e) {
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingThreads: false,
          error: mapAnyError(e, fallback: 'تعذر تحميل المحادثات.'),
        ),
      );
    }
  }

  Future<SocialChatThread?> createThreadWithUser(int userId) async {
    try {
      final out = await ref.read(socialApiProvider).createThread(userId);
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(out['thread'] as Map),
      );
      _safeSetState(
        state.copyWith(
          threads: [thread, ...state.threads.where((t) => t.id != thread.id)],
        ),
      );
      return thread;
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          error: mapDioError(
            e,
            fallback: 'تعذر بدء المحادثة.',
            customMessages: _socialApiMessages,
          ),
        ),
      );
      return null;
    } catch (e) {
      _safeSetState(
        state.copyWith(error: mapAnyError(e, fallback: 'تعذر بدء المحادثة.')),
      );
      return null;
    }
  }

  Future<SocialChatThread?> createGroupThread({
    required String title,
    required List<int> memberIds,
    String? imageUrl,
  }) async {
    try {
      final out = await ref
          .read(socialApiProvider)
          .createGroupThread(
            title: title,
            memberIds: memberIds,
            imageUrl: imageUrl,
          );
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(out['thread'] as Map),
      );
      _safeSetState(
        state.copyWith(
          threads: [thread, ...state.threads.where((t) => t.id != thread.id)],
        ),
      );
      return thread;
    } on DioException catch (e) {
      _safeSetState(
        state.copyWith(
          error: mapDioError(
            e,
            fallback: 'تعذر إنشاء المجموعة.',
            customMessages: _socialApiMessages,
          ),
        ),
      );
      return null;
    } catch (e) {
      _safeSetState(
        state.copyWith(error: mapAnyError(e, fallback: 'تعذر إنشاء المجموعة.')),
      );
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

List<SocialPost> _mergePosts(
  List<SocialPost> existing,
  List<SocialPost> incoming,
) {
  if (existing.isEmpty) return incoming;
  if (incoming.isEmpty) return existing;
  final byId = <int, SocialPost>{for (final post in existing) post.id: post};
  for (final post in incoming) {
    byId[post.id] = post;
  }
  final merged = byId.values.toList(growable: false);
  merged.sort((a, b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeCompare = bTime.compareTo(aTime);
    if (timeCompare != 0) return timeCompare;
    return b.id.compareTo(a.id);
  });
  return merged;
}
