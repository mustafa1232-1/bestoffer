import 'package:maslaki/features/social/models/social_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SocialChatAttachment parses attachment duration', () {
    final attachment = SocialChatAttachment.fromJson({
      'attachmentUrl': 'https://example.com/audio.m4a',
      'attachmentKind': 'audio',
      'attachmentName': 'clip.m4a',
      'attachmentMimeType': 'audio/mp4',
      'attachmentDurationMs': 4250,
    });

    expect(attachment.kind, 'audio');
    expect(attachment.durationMs, 4250);
  });

  test('SocialCommunityChatMessage parses nested audio attachment payload', () {
    final message = SocialCommunityChatMessage.fromJson({
      'id': 91,
      'scopeType': 'block',
      'scopeCode': 'B2',
      'senderUserId': 17,
      'body': '',
      'isMine': true,
      'isSystem': false,
      'isDeleted': false,
      'reactionTotalCount': 0,
      'sender': {
        'id': 17,
        'fullName': 'Ali Hassan',
        'role': 'user',
      },
      'attachment': {
        'attachmentUrl': 'https://example.com/voice.m4a',
        'attachmentKind': 'audio',
        'attachmentName': 'voice.m4a',
        'attachmentMimeType': 'audio/mp4',
        'attachmentDurationMs': 6100,
      },
    });

    expect(message.attachment, isNotNull);
    expect(message.attachment!.kind, 'audio');
    expect(message.attachment!.durationMs, 6100);
    expect(message.attachment!.previewLabel, contains('صوت'));
  });
}
