import '../../../core/files/local_media_file.dart';

enum LocalPendingMessageStatus { queued, uploading, sent, failed, cancelled }

class LocalPendingMessage {
  final String clientMessageId;
  final int threadId;
  final String kind;
  final LocalMediaFile? localFile;
  final String body;
  final int? durationMs;
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
    required this.uploadProgress,
    required this.status,
    required this.createdAt,
    required this.errorCode,
  });

  bool get isImage => kind.trim().toLowerCase() == 'image';
  bool get isVideo => kind.trim().toLowerCase() == 'video';
  bool get isAudio => kind.trim().toLowerCase() == 'audio';
  bool get isFile => !isImage && !isVideo && !isAudio;
  bool get isActive =>
      status == LocalPendingMessageStatus.queued ||
      status == LocalPendingMessageStatus.uploading;

  LocalPendingMessage copyWith({
    String? clientMessageId,
    int? threadId,
    String? kind,
    LocalMediaFile? localFile,
    String? body,
    int? durationMs,
    double? uploadProgress,
    LocalPendingMessageStatus? status,
    DateTime? createdAt,
    String? errorCode,
    bool clearLocalFile = false,
    bool clearErrorCode = false,
  }) {
    return LocalPendingMessage(
      clientMessageId: clientMessageId ?? this.clientMessageId,
      threadId: threadId ?? this.threadId,
      kind: kind ?? this.kind,
      localFile: clearLocalFile ? null : (localFile ?? this.localFile),
      body: body ?? this.body,
      durationMs: durationMs ?? this.durationMs,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }
}
