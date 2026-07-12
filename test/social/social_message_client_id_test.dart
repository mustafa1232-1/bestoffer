import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/ui/social_message_client_id.dart';
import 'package:social_core/social_core.dart';

void main() {
  test('buildSocialMessageClientId stays stable for the same draft payload', () {
    final attachment = LocalMediaFile(
      name: 'voice.ogg',
      path: '/tmp/voice.ogg',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'audio/ogg',
    );

    final first = buildSocialMessageClientId(
      scopeKey: 'thread:123',
      body: '',
      replyToMessageId: 77,
      attachmentFile: attachment,
      attachmentDurationMs: 2800,
      sharedEntityType: 'post',
      sharedEntityId: 42,
      sharedSnapshot: const {
        'id': 42,
        'caption': 'Hello',
        'author': {'id': 9, 'fullName': 'Alice'},
      },
    );
    final second = buildSocialMessageClientId(
      scopeKey: 'thread:123',
      body: '',
      replyToMessageId: 77,
      attachmentFile: attachment,
      attachmentDurationMs: 2800,
      sharedEntityType: 'post',
      sharedEntityId: 42,
      sharedSnapshot: const {
        'author': {'fullName': 'Alice', 'id': 9},
        'caption': 'Hello',
        'id': 42,
      },
    );

    expect(first, second);
    expect(first, startsWith('msg_'));
  });

  test('SocialChatMessage parses clientMessageId from snake and camel case', () {
    final message = SocialChatMessage.fromJson({
      'id': 501,
      'threadId': 31,
      'senderUserId': 91,
      'body': 'Phase 3B voice note',
      'client_message_id': 'msg_phase3b_501',
      'sender': {
        'id': 91,
        'fullName': 'Alice',
        'role': 'user',
      },
    });

    expect(message.clientMessageId, 'msg_phase3b_501');
    expect(message.body, 'Phase 3B voice note');

    final communityMessage = SocialCommunityChatMessage.fromJson({
      'id': 601,
      'scopeType': 'compound',
      'scopeCode': 'B1',
      'senderUserId': 92,
      'body': 'Community Phase 3B',
      'clientMessageId': 'msg_phase3b_601',
      'sender': {
        'id': 92,
        'fullName': 'Bob',
        'role': 'user',
      },
    });

    expect(communityMessage.clientMessageId, 'msg_phase3b_601');
    expect(communityMessage.body, 'Community Phase 3B');
  });
}
