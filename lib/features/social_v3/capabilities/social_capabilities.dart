import 'package:flutter/foundation.dart';

Map<String, dynamic> _stringMap(Map raw) =>
    raw.map((key, value) => MapEntry<String, dynamic>(key.toString(), value));

/// Authoritative story audience-scope capability, mirrored from the backend
/// `GET /api/feed/capabilities` response. The backend remains authoritative;
/// this is used only for UX (whether to offer scoped-story options).
@immutable
class StoryAudienceScopeCapability {
  const StoryAudienceScopeCapability({
    required this.supported,
    required this.supportedTypes,
    required this.officialStoriesSupported,
    required this.version,
    required this.reason,
  });

  final bool supported;
  final List<String> supportedTypes;
  final bool officialStoriesSupported;
  final int version;
  final String reason;

  /// Fail-closed default — used on parse errors, network failures, missing
  /// fields, and before the first fetch. A failure must NEVER enable scope.
  static const StoryAudienceScopeCapability failClosed =
      StoryAudienceScopeCapability(
        supported: false,
        supportedTypes: ['global'],
        officialStoriesSupported: false,
        version: 1,
        reason: 'UNAVAILABLE',
      );

  bool supportsType(String type) =>
      supported && supportedTypes.contains(type.trim().toLowerCase());

  factory StoryAudienceScopeCapability.fromJson(Map<String, dynamic>? j) {
    if (j == null) return failClosed;
    final supported = j['supported'] == true;
    final rawTypes = j['supportedTypes'];
    // Fail closed: if not explicitly supported, only 'global' regardless of what
    // the payload claims.
    final types = supported && rawTypes is List
        ? rawTypes
              .map((e) => '$e'.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const ['global'];
    return StoryAudienceScopeCapability(
      supported: supported,
      supportedTypes: types.isEmpty ? const ['global'] : types,
      officialStoriesSupported:
          supported && j['officialStoriesSupported'] == true,
      version: int.tryParse('${j['version']}') ?? 1,
      reason: (j['reason'] ?? '').toString(),
    );
  }
}

@immutable
class SocialCapabilities {
  const SocialCapabilities({required this.storyAudienceScope});

  final StoryAudienceScopeCapability storyAudienceScope;

  static const SocialCapabilities failClosed = SocialCapabilities(
    storyAudienceScope: StoryAudienceScopeCapability.failClosed,
  );

  factory SocialCapabilities.fromJson(Map<String, dynamic>? j) {
    final social = j?['social'];
    final scope = social is Map ? social['storyAudienceScope'] : null;
    return SocialCapabilities(
      storyAudienceScope: StoryAudienceScopeCapability.fromJson(
        scope is Map ? _stringMap(scope) : null,
      ),
    );
  }
}
