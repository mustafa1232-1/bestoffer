import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/state/social_message_snapshot.dart';
import 'package:social_core/social_models.dart';

SocialChatMessage message(int id, String body) => SocialChatMessage.fromJson({
  'id': id,
  'threadId': 7,
  'senderUserId': 2,
  'body': body,
});

void main() {
  test('HTTP cannot erase incoming messages or revert realtime edits', () {
    final original = message(1, 'before');
    final updated = message(1, 'after');
    final merged = mergeSocialMessageSnapshot(
      current: [updated, message(2, 'incoming')],
      atRequestStart: {1: original},
      snapshot: [message(1, 'stale')],
    );
    expect(merged.map((m) => m.body), ['after', 'incoming']);
  });
  test(
    'fresh snapshot updates unchanged rows; pagination cannot duplicate them',
    () {
      final original = message(3, 'before');
      final fresh = mergeSocialMessageSnapshot(
        current: [original],
        atRequestStart: {3: original},
        snapshot: [message(3, 'after')],
      );
      expect(fresh.single.body, 'after');
      final page = mergeSocialMessageSnapshot(
        current: fresh,
        atRequestStart: {3: fresh.single},
        historical: true,
        snapshot: [message(3, 'old'), message(1, 'history')],
      );
      expect(page.map((m) => m.body), ['history', 'after']);
    },
  );
}
