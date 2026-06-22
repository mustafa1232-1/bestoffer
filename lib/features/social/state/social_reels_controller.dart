import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

const Duration kSocialReelsLoadTimeout = Duration(seconds: 12);
const String kSocialReelsLoadTimeoutCode = 'REELS_LOAD_TIMEOUT';

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

  SocialReelsController(this.ref) : super(const SocialReelsState());

  Future<void> load({
    bool refresh = true,
    Duration timeout = kSocialReelsLoadTimeout,
  }) async {
    if (state.loading || state.loadingMore) return;
    final beforeId = refresh ? null : state.nextCursor;
    if (!refresh && beforeId == null) return;
    state = state.copyWith(
      loading: refresh,
      loadingMore: !refresh,
      error: null,
    );
    try {
      final out = await ref.read(socialApiProvider).listExploreReels(
            beforeId: beforeId,
          ).timeout(timeout);
      final rows = List<dynamic>.from(out['reels'] as List? ?? const []);
      final items = rows
          .map((e) => SocialReelItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        items: refresh ? items : [...state.items, ...items],
        nextCursor: int.tryParse('${out['nextCursor']}'),
        nextCursorTouched: true,
      );
    } on TimeoutException catch (_) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: kSocialReelsLoadTimeoutCode,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: '$e',
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: '$e',
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
      await ref.read(socialApiProvider).recordReelView(
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
