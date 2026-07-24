import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

class SocialExploreState {
  final bool loading;
  final SocialExplorePayload? payload;
  final List<SocialHashtag> trendingHashtags;
  final String? error;

  const SocialExploreState({
    this.loading = false,
    this.payload,
    this.trendingHashtags = const <SocialHashtag>[],
    this.error,
  });

  SocialExploreState copyWith({
    bool? loading,
    SocialExplorePayload? payload,
    bool payloadTouched = false,
    List<SocialHashtag>? trendingHashtags,
    String? error,
  }) {
    return SocialExploreState(
      loading: loading ?? this.loading,
      payload: payloadTouched ? payload : (payload ?? this.payload),
      trendingHashtags: trendingHashtags ?? this.trendingHashtags,
      error: error,
    );
  }
}

final socialExploreControllerProvider =
    StateNotifierProvider.autoDispose<SocialExploreController, SocialExploreState>(
      (ref) => SocialExploreController(ref),
    );

class SocialExploreController extends StateNotifier<SocialExploreState> {
  final Ref ref;

  SocialExploreController(this.ref) : super(const SocialExploreState());

  Future<void> load({bool refresh = false}) async {
    if (state.loading && !refresh) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final api = ref.read(socialApiProvider);
      final results = await Future.wait([
        api.listExplore(),
        api.listTrendingHashtags(),
      ]);
      final initialPayload = SocialExplorePayload.fromJson(
        Map<String, dynamic>.from(results[0]),
      );
      var payload = initialPayload;
      if (initialPayload.suggestedPeople.isEmpty) {
        final suggestedOut = await api.listSuggestedPeople();
        final suggestedRows = List<dynamic>.from(
          suggestedOut['users'] ??
          suggestedOut['people'] ??
              suggestedOut['suggestedPeople'] ??
              suggestedOut['suggested_people'] ??
              const <dynamic>[],
        );
        final suggestedPeople = suggestedRows
            .map(
              (e) => SocialUserSearchResult.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
        payload = SocialExplorePayload(
          forYou: initialPayload.forYou,
          reels: initialPayload.reels,
          trendingBasmaya: initialPayload.trendingBasmaya,
          sameArea: initialPayload.sameArea,
          restaurantReviews: initialPayload.restaurantReviews,
          popularPosts: initialPayload.popularPosts,
          localTopics: initialPayload.localTopics,
          suggestedPeople: suggestedPeople,
          generatedAt: initialPayload.generatedAt,
        );
      }
      final hashtags = List<dynamic>.from(
        results[1]['hashtags'] as List? ?? const [],
      )
          .map((e) => SocialHashtag.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      state = state.copyWith(
        loading: false,
        payload: payload,
        payloadTouched: true,
        trendingHashtags: hashtags,
      );
    } catch (_) {
      // Discovery never surfaces a technical error to the user. We keep any
      // previously loaded payload and clear the loading flag; a pull-to-refresh
      // (or the next open) retries quietly. The raw exception is intentionally
      // NOT stored — it must never reach the UI.
      state = state.copyWith(loading: false, error: null);
    }
  }

  void patchPost(SocialPost nextPost) {
    final payload = state.payload;
    if (payload == null) return;
    SocialPost replace(SocialPost item) => item.id == nextPost.id ? nextPost : item;
    state = state.copyWith(
      payloadTouched: true,
      payload: SocialExplorePayload(
        forYou: payload.forYou.map(replace).toList(growable: false),
        reels: payload.reels.map(replace).toList(growable: false),
        trendingBasmaya: payload.trendingBasmaya.map(replace).toList(growable: false),
        sameArea: payload.sameArea.map(replace).toList(growable: false),
        restaurantReviews: payload.restaurantReviews.map(replace).toList(growable: false),
        popularPosts: payload.popularPosts.map(replace).toList(growable: false),
        localTopics: payload.localTopics,
        suggestedPeople: payload.suggestedPeople,
        generatedAt: payload.generatedAt,
      ),
    );
  }

  void patchSuggestedRelation(int userId, SocialRelation relation) {
    final payload = state.payload;
    if (payload == null) return;
    state = state.copyWith(
      payloadTouched: true,
      payload: SocialExplorePayload(
        forYou: payload.forYou,
        reels: payload.reels,
        trendingBasmaya: payload.trendingBasmaya,
        sameArea: payload.sameArea,
        restaurantReviews: payload.restaurantReviews,
        popularPosts: payload.popularPosts,
        localTopics: payload.localTopics,
        suggestedPeople: payload.suggestedPeople
            .map(
              (item) => item.user.id == userId
                  ? SocialUserSearchResult(user: item.user, relation: relation)
                  : item,
            )
            .toList(growable: false),
        generatedAt: payload.generatedAt,
      ),
    );
  }
}
