import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/models/social_pending_message.dart';
import 'package:maslaki/features/social/ui/widgets/social_attachment_preview_card.dart';
import 'package:maslaki/features/social/ui/widgets/social_pending_message_bubble.dart';
import 'package:social_core/social_core.dart';

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3Z2kQAAAAASUVORK5CYII=';

Uint8List _pngBytes() => base64Decode(_onePixelPngBase64);

SocialChatMessage _chatMessage({
  required int id,
  required String clientMessageId,
  required String body,
}) {
  return SocialChatMessage.fromJson({
    'id': id,
    'threadId': 17,
    'senderUserId': 3,
    'body': body,
    'clientMessageId': clientMessageId,
    'createdAt': '2026-07-19T12:00:00.000Z',
    'updatedAt': '2026-07-19T12:00:00.000Z',
    'editedAt': null,
    'deletedAt': null,
    'pinnedAt': null,
    'pinnedByUserId': null,
    'isDeleted': false,
    'isMine': true,
    'reactions': {
      'counts': <String, int>{},
      'totalCount': 0,
    },
    'deliveredToPeer': false,
    'readByPeer': false,
    'sender': {
      'id': 3,
      'fullName': 'Tester',
      'role': 'user',
    },
  });
}

LocalPendingMessage _pendingMessage({
  required String clientMessageId,
  required int threadId,
  required String kind,
  required LocalMediaFile? localFile,
  required String body,
  int? durationMs,
  String? errorCode,
  LocalPendingMessageStatus status = LocalPendingMessageStatus.queued,
}) {
  return LocalPendingMessage(
    clientMessageId: clientMessageId,
    threadId: threadId,
    kind: kind,
    localFile: localFile,
    body: body,
    durationMs: durationMs,
    replyToMessageId: null,
    sharedEntityType: null,
    sharedEntityId: null,
    sharedSnapshot: null,
    uploadProgress: status == LocalPendingMessageStatus.sent ? 1 : 0,
    status: status,
    createdAt: DateTime.utc(2026, 7, 19, 12, 0, 0),
    errorCode: errorCode,
  );
}

void main() {
  testWidgets(
    'pending audio bubble appears before upload completes and does not render as generic file',
    (tester) async {
      final controller = LocalPendingMessageController();
      final pending = controller.enqueue(
        clientMessageId: 'audio-client-1',
        threadId: 17,
        kind: 'audio',
        localFile: const LocalMediaFile(
          name: 'voice.m4a',
          path: '/tmp/voice.m4a',
          bytes: null,
          mimeType: 'audio/mp4',
        ),
        body: 'Voice note',
        durationMs: 4200,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SocialPendingMessageBubble(message: pending),
          ),
        ),
      );

      expect(find.text('Audio'), findsOneWidget);
      // The bubble renders "<status> - <duration>" whenever the attachment has
      // a duration (see _statusLine), and this audio fixture has one, so an
      // exact-text match can never hold here.
      expect(find.textContaining('Queued'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('File'), findsNothing);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    },
  );

  testWidgets(
    'pending image bubble renders inline from local bytes and path',
    (tester) async {
      final imageBytes = _pngBytes();

      final pendingBytes = _pendingMessage(
        clientMessageId: 'image-client-bytes',
        threadId: 17,
        kind: 'image',
        localFile: LocalMediaFile(
          name: 'image-bytes.png',
          path: null,
          bytes: imageBytes,
          mimeType: 'image/png',
        ),
        body: 'Inline image bytes',
      );
      final pendingPath = _pendingMessage(
        clientMessageId: 'image-client-path',
        threadId: 17,
        kind: 'image',
        localFile: LocalMediaFile(
          name: 'image-path.png',
          path: '${Directory.systemTemp.path}${Platform.pathSeparator}social-chat-image-path.png',
          bytes: null,
          mimeType: 'image/png',
        ),
        body: 'Inline image path',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SocialPendingMessageBubble(message: pendingBytes),
                SocialPendingMessageBubble(message: pendingPath),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Image'), findsNWidgets(2));
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('File'), findsNothing);
    },
  );

  testWidgets(
    'attachment preview card renders image from bytes and path',
    (tester) async {
      final imageBytes = _pngBytes();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SocialAttachmentPreviewCard(
                  file: LocalMediaFile(
                    name: 'preview-bytes.png',
                    path: null,
                    bytes: imageBytes,
                    mimeType: 'image/png',
                  ),
                  onClear: () {},
                ),
                SocialAttachmentPreviewCard(
                  file: LocalMediaFile(
                    name: 'preview-path.png',
                    path: '${Directory.systemTemp.path}${Platform.pathSeparator}social-attachment-image-path.png',
                    bytes: null,
                    mimeType: 'image/png',
                  ),
                  onClear: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('preview-bytes.png'), findsOneWidget);
      expect(find.text('preview-path.png'), findsOneWidget);
    },
  );

  test('response-first and realtime-first reconciliation keep one logical message', () {
    final responseFirst = _chatMessage(
      id: 101,
      clientMessageId: 'client-1',
      body: 'first response',
    );
    final realtimeFirst = _chatMessage(
      id: 102,
      clientMessageId: 'client-1',
      body: 'realtime update',
    );

    final responseFirstList = upsertSocialChatMessage(<SocialChatMessage>[], responseFirst);
    final responseFirstMerged = upsertSocialChatMessage(responseFirstList, realtimeFirst);
    expect(responseFirstMerged, hasLength(1));
    expect(responseFirstMerged.single.id, 102);
    expect(responseFirstMerged.single.clientMessageId, 'client-1');

    final realtimeFirstList = upsertSocialChatMessage(<SocialChatMessage>[], realtimeFirst);
    final realtimeFirstMerged = upsertSocialChatMessage(realtimeFirstList, responseFirst);
    expect(realtimeFirstMerged, hasLength(1));
    expect(realtimeFirstMerged.single.id, 101);
    expect(realtimeFirstMerged.single.clientMessageId, 'client-1');
  });

  test('failed upload stays FAILED, retry keeps the same clientMessageId, and cancel removes it', () {
    final controller = LocalPendingMessageController();
    final pending = controller.enqueue(
      clientMessageId: 'pending-1',
      threadId: 17,
      kind: 'audio',
      localFile: const LocalMediaFile(
        name: 'voice.m4a',
        path: '/tmp/voice.m4a',
        bytes: null,
        mimeType: 'audio/mp4',
      ),
      body: 'Retry me',
      durationMs: 1800,
    );

    controller.markUploading(pending.clientMessageId);
    controller.markFailed(pending.clientMessageId, errorCode: 'NETWORK_ERROR');

    final failed = controller.byClientMessageId(pending.clientMessageId)!;
    expect(failed.status, LocalPendingMessageStatus.failed);
    expect(failed.clientMessageId, 'pending-1');
    expect(failed.kind, 'audio');

    controller.retry(pending.clientMessageId);
    final retrying = controller.byClientMessageId(pending.clientMessageId)!;
    expect(retrying.status, LocalPendingMessageStatus.uploading);
    expect(retrying.clientMessageId, 'pending-1');
    expect(retrying.kind, 'audio');

    controller.cancel(pending.clientMessageId);
    expect(controller.contains(pending.clientMessageId), isFalse);
  });

  test('fallback poll and resend helpers never change the pending attachment kind', () {
    final controller = LocalPendingMessageController();
    final pending = controller.enqueue(
      clientMessageId: 'pending-audio',
      threadId: 17,
      kind: 'audio',
      localFile: const LocalMediaFile(
        name: 'voice.m4a',
        path: '/tmp/voice.m4a',
        bytes: null,
        mimeType: 'audio/mp4',
      ),
      body: 'Kind should stay audio',
      durationMs: 2500,
    );

    controller.markUploading(pending.clientMessageId);
    controller.markFailed(pending.clientMessageId, errorCode: 'TIMEOUT');
    expect(controller.byClientMessageId(pending.clientMessageId)!.kind, 'audio');

    controller.retry(pending.clientMessageId);
    expect(controller.byClientMessageId(pending.clientMessageId)!.kind, 'audio');
  });
}
