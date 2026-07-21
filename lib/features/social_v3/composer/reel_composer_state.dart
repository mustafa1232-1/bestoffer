import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../pickers/social_media_picker_v3.dart';
import '../upload/reel_map_normalizer.dart';
import '../upload/tus_upload_client.dart';

/// Reel publication lifecycle (§4/§8), driven entirely by the backend for the
/// terminal states — Flutter never decides final publication.
enum ReelComposerStage {
  draft,
  creatingSession,
  uploading,
  paused,
  processing,
  published,
  failed,
  cancelled,
}

/// Backend contract for provisioning a Cloudflare Stream direct-upload session
/// and polling processing status. Abstracted so tests use a fake and the real
/// implementation calls `POST /feed/media/stream/upload-session` +
/// `GET /feed/media/assets/:id`.
abstract class ReelUploadApi {
  /// Provisions a one-time tus upload URL. Returns (uploadUrl, assetId).
  Future<({String uploadUrl, int assetId})> createUploadSession({
    required int sizeBytes,
    required String mimeType,
    required String fileName,
    required String idempotencyKey,
  });

  /// Current processing status of the asset ('pending'|'processing'|'ready'|'failed').
  Future<String> pollStatus(int assetId);

  /// Publishes the reel once its asset is READY. Idempotent on [idempotencyKey].
  Future<int> publishReel({
    required int assetId,
    required String caption,
    required String audience,
    required bool commentsEnabled,
    required bool sharingEnabled,
    Object? reelStyle,
    required String idempotencyKey,
  });
}

/// Factory for a [TusUploadClient] given an upload URL + size (injected for tests).
typedef TusClientFactory =
    TusUploadClient Function({
      required String uploadUrl,
      required int totalBytes,
      required int assetId,
    });

/// Orchestrates the whole reel publish flow. Testable with a fake [ReelUploadApi]
/// and a fake tus transport.
class ReelComposerController extends ChangeNotifier {
  ReelComposerController({
    required this.api,
    required this.tusFactory,
    required this.idempotencyKey,
  });

  final ReelUploadApi api;
  final TusClientFactory tusFactory;
  final String idempotencyKey;

  ReelComposerStage _stage = ReelComposerStage.draft;
  double _progress = 0;
  String? _error;
  int? _assetId;
  int? _publishedReelId;
  TusUploadClient? _tus;

  ReelComposerStage get stage => _stage;
  double get progress => _progress;
  String? get error => _error;
  int? get assetId => _assetId;
  int? get publishedReelId => _publishedReelId;

  void _set(ReelComposerStage stage, {double? progress, String? error}) {
    _stage = stage;
    if (progress != null) _progress = progress;
    _error = error;
    notifyListeners();
  }

  /// Runs draft → session → upload → processing → publish.
  Future<void> publish({
    required PickedSocialMedia video,
    required String caption,
    required String audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    Object? reelStyle,
  }) async {
    try {
      _set(ReelComposerStage.creatingSession);
      final session = await api.createUploadSession(
        sizeBytes: video.sizeBytes ?? 0,
        mimeType: video.mimeType ?? 'video/mp4',
        fileName: video.name,
        idempotencyKey: idempotencyKey,
      );
      _assetId = session.assetId;

      _set(ReelComposerStage.uploading, progress: 0);
      final tus = tusFactory(
        uploadUrl: session.uploadUrl,
        totalBytes: video.sizeBytes ?? 0,
        assetId: session.assetId,
      );
      _tus = tus;
      final sub = tus.progress.listen((p) {
        _progress = p.fraction;
        if (p.state == TusUploadState.uploading) notifyListeners();
      });
      final result = await tus.start();
      await sub.cancel();

      if (result == TusUploadState.cancelled) {
        _set(ReelComposerStage.cancelled);
        return;
      }
      if (result != TusUploadState.completed) {
        _set(ReelComposerStage.failed, error: reelUploadFailureMessage);
        return;
      }

      // Processing - the backend/webhook/reconciliation own the terminal
      // state. Wait for READY before publishing so the reel is never exposed
      // publicly with an incomplete asset.
      _set(ReelComposerStage.processing, progress: 1);

      final readyAssetId = await _waitForReadyAsset(session.assetId);
      if (readyAssetId == null) {
        _set(ReelComposerStage.failed, error: reelProcessingFailureMessage);
        return;
      }

      final normalizedReelStyle = normalizeOptionalMap(reelStyle);
      final reelId = await api.publishReel(
        assetId: readyAssetId,
        caption: caption,
        audience: audience,
        commentsEnabled: commentsEnabled,
        sharingEnabled: sharingEnabled,
        reelStyle: normalizedReelStyle,
        idempotencyKey: idempotencyKey,
      );
      _publishedReelId = reelId;
      _set(ReelComposerStage.published);
    } catch (error) {
      final failedStage = _stage;
      _debugLogReelPublishFailure(error, failedStage);
      _set(
        ReelComposerStage.failed,
        error: mapReelPublishError(error, failedStage),
      );
    }
  }

  void pauseUpload() {
    _tus?.pause();
    _set(ReelComposerStage.paused);
  }

  Future<void> resumeUpload() async {
    if (_tus == null) return;
    _set(ReelComposerStage.uploading);
    final result = await _tus!.start();
    if (result == TusUploadState.completed) {
      _set(ReelComposerStage.processing, progress: 1);
    }
  }

  Future<int?> _waitForReadyAsset(int assetId) async {
    const attempts = 30;
    for (var i = 0; i < attempts; i++) {
      final status = (await api.pollStatus(assetId)).trim().toLowerCase();
      if (status == 'ready' || status == 'published') {
        return assetId;
      }
      if (status == 'failed' ||
          status == 'rejected' ||
          status == 'deleted' ||
          status == 'expired') {
        return null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  void cancelUpload() {
    _tus?.cancel();
    _set(ReelComposerStage.cancelled);
  }

  @override
  void dispose() {
    _tus?.dispose();
    super.dispose();
  }
}

const reelInvalidResponseMessage =
    'تعذر قراءة استجابة نشر الريل. حاول مرة أخرى.';
const reelNetworkMessage =
    'تعذر الاتصال أثناء رفع الريل. تحقق من الإنترنت وحاول مجدداً.';
const reelUploadFailureMessage = 'تعذر رفع الفيديو. يمكنك إعادة المحاولة.';
const reelProcessingFailureMessage = 'تعذرت معالجة الفيديو حالياً.';
const reelSessionRecoveryMessage =
    'جارٍ استعادة الجلسة. حاول النشر مجدداً بعد لحظات.';
const reelServerFailureMessage = 'تعذر نشر الريل حالياً.';

String mapReelPublishError(Object error, ReelComposerStage stage) {
  if (error is ReelInvalidResponseException || error is FormatException) {
    return reelInvalidResponseMessage;
  }
  if (error is StateError && '$error'.contains('INVALID_RESPONSE')) {
    return reelInvalidResponseMessage;
  }
  if (error is TusExpiredUploadException) {
    return reelUploadFailureMessage;
  }
  if (error is DioException) {
    final statusCode = error.response?.statusCode ?? 0;
    if (statusCode == 401 || statusCode == 419) {
      return reelSessionRecoveryMessage;
    }
    if (_isNetworkDioError(error)) {
      return reelNetworkMessage;
    }
    if (stage == ReelComposerStage.uploading) {
      return reelUploadFailureMessage;
    }
    if (stage == ReelComposerStage.processing) {
      return reelProcessingFailureMessage;
    }
    return reelServerFailureMessage;
  }
  if (stage == ReelComposerStage.uploading) {
    return reelUploadFailureMessage;
  }
  if (stage == ReelComposerStage.processing) {
    return reelProcessingFailureMessage;
  }
  return reelServerFailureMessage;
}

bool _isNetworkDioError(DioException error) {
  if (error.response != null) return false;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => true,
    _ => false,
  };
}

void _debugLogReelPublishFailure(Object error, ReelComposerStage stage) {
  if (!kDebugMode) return;
  if (error is DioException) {
    debugPrint(
      '[reel-publish] failed stage=${stage.name} '
      'errorType=${error.runtimeType} dioType=${error.type.name} '
      'status=${error.response?.statusCode ?? 0}',
    );
    return;
  }
  if (error is ReelInvalidResponseException) {
    debugPrint(
      '[reel-publish] failed stage=${stage.name} '
      'errorType=${error.runtimeType} code=${error.code}',
    );
    return;
  }
  debugPrint(
    '[reel-publish] failed stage=${stage.name} '
    'errorType=${error.runtimeType}',
  );
}
