import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

const Duration kSocialReelsLoadTimeout = Duration(seconds: 12);
const String kSocialReelsLoadTimeoutCode = 'REELS_LOAD_TIMEOUT';
const String kSocialReelsLoadNetworkCode = 'REELS_LOAD_NETWORK';
const String kSocialReelsLoadAuthCode = 'REELS_LOAD_AUTH';
const String kSocialReelsLoadServerCode = 'REELS_LOAD_SERVER';
const String kSocialReelsLoadFailedCode = 'REELS_LOAD_FAILED';

class SocialReelsState {
  final bool loading;
  final bool loadingMore;
  final List<SocialReelItem> items;
  final int? nextCursor;
  final String? error;

  const SocialReelsState({
    this.loading = false,
    this.loadingMore = false,
    this.items = const <SocialReelItem>[],
    this.nextCursor,
    this.error,
  });

  SocialReelsState copyWith({
    bool? loading,
    bool? loadingMore,
    List<SocialReelItem>? items,
    int? nextCursor,
    bool nextCursorTouched = false,
    String? error,
  }) {
    return SocialReelsState(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      items: items ?? this.items,
      nextCursor: nextCursorTouched ? nextCursor : this.nextCursor,
      error: error,
    );
  }
}

final socialReelsControllerProvider =
    StateNotifierProvider.autoDispose<SocialReelsController, SocialReelsState>(
      (ref) => SocialReelsController(ref),
    );

class SocialReelsController extends StateNotifier<SocialReelsState> {
  final Ref ref;
  int _loadGeneration = 0;

  SocialReelsController(this.ref) : super(const SocialReelsState());

  Future<void> load({
    bool refresh = true,
    Duration timeout = kSocialReelsLoadTimeout,
  }) async {
    if (state.loading || state.loadingMore) return;
    final generation = ++_loadGeneration;
    final beforeId = refresh ? null : state.nextCursor;
    if (!refresh && beforeId == null) return;
    state = state.copyWith(
      loading: refresh,
      loadingMore: !refresh,
      error: null,
    );
    try {
      final out = await ref
          .read(socialApiProvider)
          .listExploreReels(beforeId: beforeId)
          .timeout(timeout);
      final rows = List<dynamic>.from(out['reels'] as List? ?? const []);
      final items = rows
          .map(
            (e) => SocialReelItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        items: refresh
            ? _mergeReels(const <SocialReelItem>[], items)
            : _mergeReels(state.items, items),
        nextCursor: int.tryParse('${out['nextCursor']}'),
        nextCursorTouched: true,
      );
    } on TimeoutException catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: kSocialReelsLoadTimeoutCode,
      );
    } on DioException catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: _mapReelsLoadDioError(e),
      );
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: kSocialReelsLoadFailedCode,
      );
    }
  }

  Future<void> loadMore() => load(refresh: false);

  void patchPost(SocialPost nextPost) {
    state = state.copyWith(
      items: state.items
          .map(
            (item) => item.post.id == nextPost.id
                ? SocialReelItem(post: nextPost, metrics: item.metrics)
                : item,
          )
          .toList(growable: false),
    );
  }

  Future<void> recordView({
    required int reelId,
    int? watchDurationMs,
    double? completionRate,
    bool? completed,
    int? replayCount,
    String context = 'reel_viewer',
  }) async {
    try {
      await ref
          .read(socialApiProvider)
          .recordReelView(
            reelId: reelId,
            watchDurationMs: watchDurationMs,
            completionRate: completionRate,
            completed: completed,
            replayCount: replayCount,
            context: context,
          );
    } catch (_) {
      // keep viewer responsive
    }
  }
}

String _mapReelsLoadDioError(DioException error) {
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return kSocialReelsLoadNetworkCode;
  }
  final statusCode = error.response?.statusCode ?? 0;
  if (statusCode == 401) return kSocialReelsLoadAuthCode;
  if (statusCode == 502 || statusCode == 503 || statusCode >= 500) {
    return kSocialReelsLoadServerCode;
  }
  return kSocialReelsLoadFailedCode;
}

List<SocialReelItem> _mergeReels(
  List<SocialReelItem> existing,
  List<SocialReelItem> incoming,
) {
  if (existing.isEmpty) return incoming;
  if (incoming.isEmpty) return existing;
  final byId = <int, SocialReelItem>{
    for (final item in existing) item.post.id: item,
  };
  for (final item in incoming) {
    byId[item.post.id] = item;
  }
  final merged = byId.values.toList(growable: false);
  merged.sort((a, b) {
    final aTime = a.post.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.post.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeCompare = bTime.compareTo(aTime);
    if (timeCompare != 0) return timeCompare;
    return b.post.id.compareTo(a.post.id);
  });
  return merged;
}
