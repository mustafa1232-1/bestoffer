import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/models/social_models.dart';

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
    expect(attachment.effectiveKind, 'audio');
    expect(attachment.previewLabel, contains('صوت'));
  });

  test('SocialChatAttachment infers image and video from metadata', () {
    final image = SocialChatAttachment.fromJson({
      'attachmentUrl': 'https://example.com/photo.jpg',
      'attachmentKind': 'file',
      'attachmentName': 'photo.jpg',
      'attachmentMimeType': 'image/jpeg',
    });
    final video = SocialChatAttachment.fromJson({
      'attachmentUrl': 'https://example.com/clip.mp4',
      'attachmentKind': 'file',
      'attachmentName': 'clip.mp4',
      'attachmentMimeType': 'video/mp4',
      'attachmentPreviewUrl': 'https://example.com/clip-thumb.jpg',
      'attachmentThumbnailUrl': 'https://example.com/clip-thumb.jpg',
      'attachmentUploadState': 'ready',
      'attachmentTraceId': 'trace-123',
    });

    expect(image.effectiveKind, 'image');
    expect(image.previewLabel, contains('صورة'));
    expect(video.effectiveKind, 'video');
    expect(video.previewLabel, contains('فيديو'));
    expect(video.normalizedUploadState, 'ready');
    expect(video.traceId, 'trace-123');
    expect(video.resolvedPreviewUrl, 'https://example.com/clip-thumb.jpg');
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
        'attachmentProvider': 'stream',
        'attachmentPreviewUrl': 'https://example.com/voice-preview.jpg',
        'attachmentThumbnailUrl': 'https://example.com/voice-preview.jpg',
        'attachmentUploadState': 'ready',
        'attachmentTraceId': 'voice-trace-1',
      },
    });

    expect(message.attachment, isNotNull);
    expect(message.attachment!.kind, 'audio');
    expect(message.attachment!.durationMs, 6100);
    expect(message.attachment!.effectiveKind, 'audio');
    expect(message.attachment!.previewLabel, contains('صوت'));
    expect(message.attachment!.normalizedProvider, 'stream');
    expect(message.attachment!.resolvedPreviewUrl, isNotNull);
    expect(message.attachment!.traceId, 'voice-trace-1');
  });
}
