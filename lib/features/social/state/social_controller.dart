import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/social_api.dart';
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
  'EMPTY_STORY': 'أضف نصًا أو صورة/فيديو قبل نشر الستوري.',
  'STORY_NOT_FOUND': 'الستوري غير متاحة حالياً.',
};

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

class SocialController extends StateNotifier<SocialState> {
  final Ref ref;
  bool _disposed = false;

  SocialController(this.ref) : super(const SocialState());

  void _safeSetState(SocialState next) {
    if (_disposed) return;
    state = next;
  }

  Future<void> bootstrap() async {
    await Future.wait([loadStories(), loadPosts(refresh: true), loadThreads()]);
  }

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

      final merged = loadingMore ? [...state.posts, ...parsed] : parsed;
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
      if (silent) return;
      _safeSetState(
        state.copyWith(
          loadingPosts: false,
          loadingMorePosts: false,
          error: mapDioError(
            e,
            fallback: 'تعذر تحميل منشورات شديصير بسماية.',
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
    LocalMediaFile? mediaFile,
  }) async {
    _safeSetState(state.copyWith(creatingStory: true, error: null));
    try {
      await ref
          .read(socialApiProvider)
          .createStory(caption: caption, mediaFile: mediaFile);
      _safeSetState(state.copyWith(creatingStory: false));
      await loadStories();
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
    LocalMediaFile? mediaFile,
  }) async {
    _safeSetState(state.copyWith(creatingPost: true, error: null));
    try {
      final out = await ref
          .read(socialApiProvider)
          .createPost(
            caption: caption,
            postKind: postKind,
            merchantId: merchantId,
            reviewRating: reviewRating,
            mediaFile: mediaFile,
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

  Future<void> loadThreads() async {
    _safeSetState(state.copyWith(loadingThreads: true, error: null));
    try {
      final out = await ref.read(socialApiProvider).listThreads();
      final raw = List<dynamic>.from(out['threads'] as List? ?? const []);
      final threads = raw
          .map(
            (e) =>
                SocialChatThread.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
      _safeSetState(state.copyWith(loadingThreads: false, threads: threads));
    } on DioException catch (e) {
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
