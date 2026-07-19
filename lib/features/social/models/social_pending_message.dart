import 'package:flutter/foundation.dart';

import 'package:social_core/social_core.dart';

enum LocalPendingMessageStatus { queued, uploading, sent, failed, cancelled }

class LocalPendingMessage {
  final String clientMessageId;
  final int threadId;
  final String kind;
  final LocalMediaFile? localFile;
  final String body;
  final int? durationMs;
  final int? replyToMessageId;
  final String? sharedEntityType;
  final int? sharedEntityId;
  final Map<String, dynamic>? sharedSnapshot;
  final double uploadProgress;
  final LocalPendingMessageStatus status;
  final DateTime createdAt;
  final String? errorCode;

  const LocalPendingMessage({
    required this.clientMessageId,
    required this.threadId,
    required this.kind,
    required this.localFile,
    required this.body,
    required this.durationMs,
    required this.replyToMessageId,
    required this.sharedEntityType,
    required this.sharedEntityId,
    required this.sharedSnapshot,
    required this.uploadProgress,
    required this.status,
    required this.createdAt,
    required this.errorCode,
  });

  bool get isAudio => kind.trim().toLowerCase() == 'audio';
  bool get isImage => kind.trim().toLowerCase() == 'image';
  bool get isVideo => kind.trim().toLowerCase() == 'video';
  bool get isText => kind.trim().toLowerCase() == 'text';
  bool get isFile => !isAudio && !isImage && !isVideo && !isText;

  LocalPendingMessage copyWith({
    String? clientMessageId,
    int? threadId,
    String? kind,
    LocalMediaFile? localFile,
    String? body,
    int? durationMs,
    int? replyToMessageId,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
    bool clearSharedSnapshot = false,
    double? uploadProgress,
    LocalPendingMessageStatus? status,
    DateTime? createdAt,
    String? errorCode,
    bool clearErrorCode = false,
  }) {
    return LocalPendingMessage(
      clientMessageId: clientMessageId ?? this.clientMessageId,
      threadId: threadId ?? this.threadId,
      kind: kind ?? this.kind,
      localFile: localFile ?? this.localFile,
      body: body ?? this.body,
      durationMs: durationMs ?? this.durationMs,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      sharedEntityType: sharedEntityType ?? this.sharedEntityType,
      sharedEntityId: sharedEntityId ?? this.sharedEntityId,
      sharedSnapshot: clearSharedSnapshot
          ? null
          : (sharedSnapshot ?? this.sharedSnapshot),
      uploadProgress: uploadProgress ?? this.uploadProgress,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }
}

class LocalPendingMessageController extends ChangeNotifier {
  final List<LocalPendingMessage> _items = <LocalPendingMessage>[];

  List<LocalPendingMessage> get items =>
      List<LocalPendingMessage>.unmodifiable(_items);

  LocalPendingMessage enqueue({
    required String clientMessageId,
    required int threadId,
    required String kind,
    required LocalMediaFile? localFile,
    required String body,
    required int? durationMs,
    int? replyToMessageId,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
  }) {
    final pending = LocalPendingMessage(
      clientMessageId: clientMessageId.trim(),
      threadId: threadId,
      kind: kind.trim().toLowerCase(),
      localFile: localFile,
      body: body,
      durationMs: durationMs,
      replyToMessageId: replyToMessageId,
      sharedEntityType: sharedEntityType,
      sharedEntityId: sharedEntityId,
      sharedSnapshot: sharedSnapshot,
      uploadProgress: 0,
      status: LocalPendingMessageStatus.queued,
      createdAt: DateTime.now(),
      errorCode: null,
    );
    _items.add(pending);
    notifyListeners();
    return pending;
  }

  bool contains(String clientMessageId) => _indexOf(clientMessageId) >= 0;

  LocalPendingMessage? byClientMessageId(String clientMessageId) {
    final index = _indexOf(clientMessageId);
    return index < 0 ? null : _items[index];
  }

  void markUploading(String clientMessageId, {double uploadProgress = 0}) {
    _replace(clientMessageId, (current) => current.copyWith(
          status: LocalPendingMessageStatus.uploading,
          uploadProgress: uploadProgress,
          clearErrorCode: true,
        ));
  }

  void markSent(String clientMessageId) {
    _replace(clientMessageId, (current) => current.copyWith(
          status: LocalPendingMessageStatus.sent,
          uploadProgress: 1,
          clearErrorCode: true,
        ));
  }

  void markFailed(String clientMessageId, {String? errorCode}) {
    _replace(clientMessageId, (current) => current.copyWith(
          status: LocalPendingMessageStatus.failed,
          uploadProgress: current.uploadProgress,
          errorCode: errorCode,
        ));
  }

  void retry(String clientMessageId) {
    _replace(clientMessageId, (current) => current.copyWith(
          status: LocalPendingMessageStatus.uploading,
          uploadProgress: 0,
          clearErrorCode: true,
        ));
  }

  void cancel(String clientMessageId) {
    final index = _indexOf(clientMessageId);
    if (index < 0) return;
    _items.removeAt(index);
    notifyListeners();
  }

  bool reconcileServerMessage(SocialChatMessage message) {
    final clientId = (message.clientMessageId ?? '').trim();
    if (clientId.isEmpty) return false;
    final index = _indexOf(clientId);
    if (index < 0) return false;
    _items.removeAt(index);
    notifyListeners();
    return true;
  }

  void clearThread(int threadId) {
    final before = _items.length;
    _items.removeWhere((item) => item.threadId == threadId);
    if (_items.length != before) {
      notifyListeners();
    }
  }

  int _indexOf(String clientMessageId) {
    final target = clientMessageId.trim();
    if (target.isEmpty) return -1;
    return _items.indexWhere((item) => item.clientMessageId == target);
  }

  void _replace(
    String clientMessageId,
    LocalPendingMessage Function(LocalPendingMessage current) transform,
  ) {
    final index = _indexOf(clientMessageId);
    if (index < 0) return;
    _items[index] = transform(_items[index]);
    notifyListeners();
  }
}

List<SocialChatMessage> upsertSocialChatMessage(
  List<SocialChatMessage> current,
  SocialChatMessage next,
) {
  final out = List<SocialChatMessage>.of(current);
  final normalizedClientId = (next.clientMessageId ?? '').trim();
  if (normalizedClientId.isNotEmpty) {
    final clientIndex = out.indexWhere(
      (message) => (message.clientMessageId ?? '').trim() == normalizedClientId,
    );
    if (clientIndex >= 0) {
      out[clientIndex] = next;
      out.sort((a, b) => a.id.compareTo(b.id));
      return out;
    }
  }

  final idIndex = out.indexWhere((message) => message.id == next.id);
  if (idIndex >= 0) {
    out[idIndex] = next;
  } else {
    out.add(next);
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

String pendingAttachmentKindForFile(LocalMediaFile file) {
  if (file.isAudio) return 'audio';
  if (file.isImage) return 'image';
  if (file.isVideo) return 'video';
  return 'file';
}
