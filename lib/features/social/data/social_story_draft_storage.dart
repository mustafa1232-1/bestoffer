import 'dart:convert';

import '../../../core/storage/secure_storage.dart';
import '../models/social_story_document.dart';

class SocialStoryDraftStorage {
  static const _lastDraftKey = 'social_story_draft_v2';
  final SecureStore _store;

  const SocialStoryDraftStorage(this._store);

  Future<void> save(SocialStoryDraft draft) async {
    await _store.writeString(_lastDraftKey, jsonEncode(draft.toJson()));
  }

  Future<SocialStoryDraft?> load() async {
    final raw = await _store.readString(_lastDraftKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SocialStoryDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _store.delete(_lastDraftKey);
}
