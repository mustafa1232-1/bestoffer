import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

class SocialSavedState {
  final bool loading;
  final bool mutating;
  final List<SocialSavedCollection> collections;
  final List<SocialSavedItem> items;
  final String? entityType;
  final int? collectionId;
  final int? nextCursor;
  final String? error;

  const SocialSavedState({
    this.loading = false,
    this.mutating = false,
    this.collections = const <SocialSavedCollection>[],
    this.items = const <SocialSavedItem>[],
    this.entityType,
    this.collectionId,
    this.nextCursor,
    this.error,
  });

  SocialSavedState copyWith({
    bool? loading,
    bool? mutating,
    List<SocialSavedCollection>? collections,
    List<SocialSavedItem>? items,
    String? entityType,
    bool entityTypeTouched = false,
    int? collectionId,
    bool collectionIdTouched = false,
    int? nextCursor,
    bool nextCursorTouched = false,
    String? error,
  }) {
    return SocialSavedState(
      loading: loading ?? this.loading,
      mutating: mutating ?? this.mutating,
      collections: collections ?? this.collections,
      items: items ?? this.items,
      entityType: entityTypeTouched ? entityType : this.entityType,
      collectionId: collectionIdTouched ? collectionId : this.collectionId,
      nextCursor: nextCursorTouched ? nextCursor : this.nextCursor,
      error: error,
    );
  }
}

final socialSavedControllerProvider =
    StateNotifierProvider.autoDispose<SocialSavedController, SocialSavedState>(
      (ref) => SocialSavedController(ref),
    );

class SocialSavedController extends StateNotifier<SocialSavedState> {
  final Ref ref;

  SocialSavedController(this.ref) : super(const SocialSavedState());

  Future<void> load({
    bool refresh = true,
    String? entityType,
    int? collectionId,
  }) async {
    if (state.loading || state.mutating) return;
    final effectiveEntityType = entityType ?? state.entityType;
    final effectiveCollectionId = collectionId ?? state.collectionId;
    final beforeId = refresh ? null : state.nextCursor;
    if (!refresh && beforeId == null) return;
    state = state.copyWith(
      loading: true,
      entityType: effectiveEntityType,
      entityTypeTouched: true,
      collectionId: effectiveCollectionId,
      collectionIdTouched: true,
      error: null,
    );
    try {
      final api = ref.read(socialApiProvider);
      final responses = await Future.wait([
        api.listSavedCollections(),
        api.listSaved(
          entityType: effectiveEntityType,
          collectionId: effectiveCollectionId,
          beforeId: beforeId,
        ),
      ]);
      final collections = List<dynamic>.from(
        responses[0]['collections'] as List? ?? const [],
      )
          .map(
            (e) => SocialSavedCollection.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      final items = List<dynamic>.from(responses[1]['items'] as List? ?? const [])
          .map((e) => SocialSavedItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      state = state.copyWith(
        loading: false,
        collections: collections,
        items: refresh ? items : [...state.items, ...items],
        nextCursor: int.tryParse('${responses[1]['nextCursor']}'),
        nextCursorTouched: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> refresh() => load(
        refresh: true,
        entityType: state.entityType,
        collectionId: state.collectionId,
      );

  Future<void> createCollection({
    required String title,
    String? description,
  }) async {
    state = state.copyWith(mutating: true, error: null);
    try {
      await ref.read(socialApiProvider).createSavedCollection(
            title: title,
            description: description,
          );
      state = state.copyWith(mutating: false);
      await refresh();
    } catch (e) {
      state = state.copyWith(mutating: false, error: '$e');
    }
  }

  Future<void> renameCollection({
    required int collectionId,
    required String title,
    String? description,
  }) async {
    state = state.copyWith(mutating: true, error: null);
    try {
      await ref.read(socialApiProvider).updateSavedCollection(
            collectionId: collectionId,
            title: title,
            description: description,
          );
      state = state.copyWith(mutating: false);
      await refresh();
    } catch (e) {
      state = state.copyWith(mutating: false, error: '$e');
    }
  }

  Future<void> deleteCollection(int collectionId) async {
    state = state.copyWith(mutating: true, error: null);
    try {
      await ref.read(socialApiProvider).deleteSavedCollection(collectionId);
      state = state.copyWith(mutating: false);
      await refresh();
    } catch (e) {
      state = state.copyWith(mutating: false, error: '$e');
    }
  }

  Future<bool> toggleSaved({
    required String entityType,
    required int entityId,
    List<int> collectionIds = const <int>[],
  }) async {
    state = state.copyWith(mutating: true, error: null);
    try {
      final out = await ref.read(socialApiProvider).toggleSaved(
            entityType: entityType,
            entityId: entityId,
            collectionIds: collectionIds,
          );
      state = state.copyWith(mutating: false);
      await refresh();
      return out['saved'] == true;
    } catch (e) {
      state = state.copyWith(mutating: false, error: '$e');
      return false;
    }
  }
}
