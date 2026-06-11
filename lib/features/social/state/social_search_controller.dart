import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

class SocialSearchState {
  final bool loading;
  final String query;
  final String tab;
  final SocialSearchResults? results;
  final String? error;

  const SocialSearchState({
    this.loading = false,
    this.query = '',
    this.tab = 'all',
    this.results,
    this.error,
  });

  SocialSearchState copyWith({
    bool? loading,
    String? query,
    String? tab,
    SocialSearchResults? results,
    bool resultsTouched = false,
    String? error,
  }) {
    return SocialSearchState(
      loading: loading ?? this.loading,
      query: query ?? this.query,
      tab: tab ?? this.tab,
      results: resultsTouched ? results : (results ?? this.results),
      error: error,
    );
  }
}

final socialSearchControllerProvider =
    StateNotifierProvider.autoDispose<SocialSearchController, SocialSearchState>(
      (ref) => SocialSearchController(ref),
    );

class SocialSearchController extends StateNotifier<SocialSearchState> {
  final Ref ref;

  SocialSearchController(this.ref) : super(const SocialSearchState());

  Future<void> search({
    required String query,
    String? tab,
  }) async {
    final effectiveTab = tab ?? state.tab;
    state = state.copyWith(
      loading: true,
      query: query,
      tab: effectiveTab,
      error: null,
    );
    try {
      final out = await ref.read(socialApiProvider).searchSocial(
            search: query,
            tab: effectiveTab,
          );
      state = state.copyWith(
        loading: false,
        results: SocialSearchResults.fromJson(out),
        resultsTouched: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> setTab(String tab) async {
    await search(query: state.query, tab: tab);
  }
}
