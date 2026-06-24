import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/models/social_models.dart';

void main() {
  group('Social chat identity resolution', () {
    test('recomputes isMine from senderUserId for the active viewer', () {
      final message = SocialChatMessage.fromJson({
        'id': 10,
        'threadId': 99,
        'senderUserId': 41,
        'body': 'hello',
        'isMine': false,
        'sender': {'id': 0, 'fullName': '', 'role': ''},
      });

      final resolved = message.resolvedForViewer(
        viewerUserId: 41,
        selfAuthor: SocialAuthor.fromJson({
          'id': 41,
          'fullName': 'Current User',
          'imageUrl': 'https://example.com/me.png',
          'role': 'user',
        }),
      );

      expect(resolved.isMine, isTrue);
      expect(resolved.sender.id, 41);
      expect(resolved.sender.fullName, 'Current User');
      expect(resolved.sender.imageUrl, 'https://example.com/me.png');
    });

    test('hydrates missing peer sender data from fallback author', () {
      final message = SocialChatMessage.fromJson({
        'id': 11,
        'threadId': 99,
        'senderUserId': 77,
        'body': 'hi there',
        'isMine': false,
        'sender': {'id': 0, 'fullName': '', 'imageUrl': '', 'role': ''},
      });

      final resolved = message.resolvedForViewer(
        viewerUserId: 41,
        peerAuthor: SocialAuthor.fromJson({
          'id': 77,
          'username': 'other_user',
          'fullName': 'Other User',
          'imageUrl': 'https://example.com/other.png',
          'role': 'user',
        }),
      );

      expect(resolved.isMine, isFalse);
      expect(resolved.sender.id, 77);
      expect(resolved.sender.username, 'other_user');
      expect(resolved.sender.fullName, 'Other User');
      expect(resolved.sender.imageUrl, 'https://example.com/other.png');
    });

    test('hydrates incomplete thread peer from route fallback', () {
      final thread = SocialChatThread.fromJson({
        'id': 99,
        'threadKind': 'private',
        'contextType': 'none',
        'contextId': 0,
        'contextStatus': 'active',
        'peer': {'id': 0, 'fullName': '', 'imageUrl': '', 'role': ''},
        'peerPhone': '',
        'presence': const {},
        'state': const {},
      });

      final resolved = thread.resolvedWithPeerFallback(
        SocialAuthor.fromJson({
          'id': 77,
          'username': 'other_user',
          'fullName': 'Other User',
          'imageUrl': 'https://example.com/other.png',
          'phone': '+9647000000000',
          'role': 'user',
        }),
      );

      expect(resolved.peer.id, 77);
      expect(resolved.peer.username, 'other_user');
      expect(resolved.peer.fullName, 'Other User');
      expect(resolved.peer.imageUrl, 'https://example.com/other.png');
      expect(resolved.displayTitle, '@other_user');
    });
  });
}
