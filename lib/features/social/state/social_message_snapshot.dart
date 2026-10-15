import 'package:social_core/social_models.dart';

/// Realtime edits arriving during an HTTP read take precedence over its older
/// snapshot. Historical pagination also cannot replace an already loaded row.
List<SocialChatMessage> mergeSocialMessageSnapshot({
  required List<SocialChatMessage> current,
  required Map<int, SocialChatMessage> atRequestStart,
  required List<SocialChatMessage> snapshot,
  bool historical = false,
}) {
  final merged = {for (final message in current) message.id: message};
  for (final message in snapshot) {
    final existing = merged[message.id];
    if (existing != null &&
        (historical || !identical(existing, atRequestStart[message.id]))) {
      continue;
    }
    merged[message.id] = message;
  }
  return merged.values.toList()..sort((a, b) => a.id.compareTo(b.id));
}
