import 'package:flutter/foundation.dart';

@immutable
class ActiveChatContext {
  final int? socialThreadId;
  final String? communityScopeKey;

  const ActiveChatContext({this.socialThreadId, this.communityScopeKey});

  ActiveChatContext copyWith({
    int? socialThreadId,
    bool clearSocialThread = false,
    String? communityScopeKey,
    bool clearCommunityScope = false,
  }) {
    return ActiveChatContext(
      socialThreadId: clearSocialThread
          ? null
          : (socialThreadId ?? this.socialThreadId),
      communityScopeKey: clearCommunityScope
          ? null
          : (communityScopeKey ?? this.communityScopeKey),
    );
  }
}

class ActiveChatContextRegistry {
  ActiveChatContextRegistry._();

  static final ValueNotifier<ActiveChatContext> _value = ValueNotifier(
    const ActiveChatContext(),
  );

  static ValueListenable<ActiveChatContext> get listenable => _value;

  static ActiveChatContext get current => _value.value;

  static void enterSocialThread(int threadId) {
    if (threadId <= 0) return;
    if (_value.value.socialThreadId == threadId) return;
    _value.value = _value.value.copyWith(socialThreadId: threadId);
  }

  static void leaveSocialThread(int threadId) {
    if (threadId <= 0) return;
    if (_value.value.socialThreadId != threadId) return;
    _value.value = _value.value.copyWith(clearSocialThread: true);
  }

  static void enterCommunityScope({
    required String scopeType,
    required String scopeCode,
  }) {
    final key = normalizeScopeKey(scopeType: scopeType, scopeCode: scopeCode);
    if (key == null) return;
    if (_value.value.communityScopeKey == key) return;
    _value.value = _value.value.copyWith(communityScopeKey: key);
  }

  static void leaveCommunityScope({
    required String scopeType,
    required String scopeCode,
  }) {
    final key = normalizeScopeKey(scopeType: scopeType, scopeCode: scopeCode);
    if (key == null) return;
    if (_value.value.communityScopeKey != key) return;
    _value.value = _value.value.copyWith(clearCommunityScope: true);
  }

  static bool matchesPayload({
    String? target,
    String? type,
    int? threadId,
    String? scopeType,
    String? scopeCode,
  }) {
    final normalizedTarget = (target ?? '').trim().toLowerCase();
    final normalizedType = (type ?? '').trim().toLowerCase();

    final isDirectChat =
        normalizedTarget == 'social_chat' ||
        normalizedType.startsWith('social.chat.');
    if (isDirectChat) {
      final activeThreadId = _value.value.socialThreadId;
      return activeThreadId != null &&
          threadId != null &&
          threadId > 0 &&
          activeThreadId == threadId;
    }

    final isCommunityChat =
        normalizedTarget == 'social_community' ||
        normalizedType.startsWith('social.community.chat.');
    if (isCommunityChat) {
      final activeScope = _value.value.communityScopeKey;
      final payloadScope = normalizeScopeKey(
        scopeType: scopeType,
        scopeCode: scopeCode,
      );
      return activeScope != null &&
          payloadScope != null &&
          activeScope == payloadScope;
    }

    return false;
  }

  static String? normalizeScopeKey({
    required String? scopeType,
    required String? scopeCode,
  }) {
    final safeType = (scopeType ?? '').trim().toLowerCase();
    final safeCode = (scopeCode ?? '').trim().toUpperCase();
    if (safeType.isEmpty || safeCode.isEmpty) return null;
    return '$safeType::$safeCode';
  }
}
