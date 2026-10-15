import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../pickers/social_media_picker_v3.dart';
import '../upload/reel_map_normalizer.dart';
import '../upload/tus_upload_client.dart';

/// Reel publication lifecycle (§4/§8), driven entirely by the backend for the
/// terminal states — Flutter never decides final publication.
enum ReelComposerStage {
  draft,
  preparing,
  creatingSession,
  uploading,
  paused,
  processing,
  publishing,
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
      required PickedSocialMedia video,
    });

typedef ReelVideoPreparer =
    Future<PickedSocialMedia> Function(
      void Function(double) onProgress,
      CancelToken cancelToken,
    );

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
  _ReelPublishRequest? _pendingPublishRequest;
  TusUploadClient? _tus;
  StreamSubscription<TusProgress>? _progressSubscription;
  bool _disposed = false;
  bool _running = false;
  int _generation = 0;
  CancelToken? _preparationCancel;
  String? _uploadSourceSignature;
  int _uploadSourceRevision = 0;

  ReelComposerStage get stage => _stage;
  double get progress => _progress;
  String? get error => _error;
  int? get assetId => _assetId;
  int? get publishedReelId => _publishedReelId;
  bool get canCancel =>
      !_disposed &&
      _stage != ReelComposerStage.publishing &&
      _stage != ReelComposerStage.published;

  void _set(ReelComposerStage stage, {double? progress, String? error}) {
    if (_disposed) return;
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
    ReelVideoPreparer? prepareVideo,
  }) async {
    if (_disposed || _running || _stage == ReelComposerStage.published) return;
    _running = true;
    final generation = ++_generation;
    try {
      var uploadVideo = video;
      if (prepareVideo != null) {
        _set(ReelComposerStage.preparing, progress: 0);
        final cancellation = CancelToken();
        _preparationCancel = cancellation;
        uploadVideo = await prepareVideo((progress) {
          if (_isCurrent(generation) &&
              _stage == ReelComposerStage.preparing &&
              progress.isFinite) {
            _set(ReelComposerStage.preparing, progress: progress.clamp(0, 1));
          }
        }, cancellation);
        if (!_isCurrent(generation)) return;
      }
      final request = _ReelPublishRequest(
        caption: caption,
        audience: audience,
        commentsEnabled: commentsEnabled,
        sharingEnabled: sharingEnabled,
        reelStyle: normalizeOptionalMap(reelStyle),
      );
      _pendingPublishRequest = request;
      final signature =
          '${uploadVideo.path}\n${uploadVideo.sizeBytes}\n${uploadVideo.mimeType}';
      if (_uploadSourceSignature != null &&
          _uploadSourceSignature != signature) {
        _uploadSourceRevision++;
      }
      _uploadSourceSignature = signature;
      _set(ReelComposerStage.creatingSession);
      final session = await api.createUploadSession(
        sizeBytes: uploadVideo.sizeBytes ?? 0,
        mimeType: uploadVideo.mimeType ?? 'video/mp4',
        fileName: uploadVideo.name,
        idempotencyKey: _uploadSourceRevision == 0
            ? idempotencyKey
            : '$idempotencyKey-source-$_uploadSourceRevision',
      );
      if (!_isCurrent(generation)) return;
      _assetId = session.assetId;

      _set(ReelComposerStage.uploading, progress: 0);
      _tus?.dispose();
      final tus = tusFactory(
        uploadUrl: session.uploadUrl,
        totalBytes: uploadVideo.sizeBytes ?? 0,
        assetId: session.assetId,
        video: uploadVideo,
      );
      _tus = tus;
      final result = await _upload(tus, generation);
      if (!_isCurrent(generation)) return;

      if (result == TusUploadState.cancelled) {
        _set(ReelComposerStage.cancelled);
        return;
      }
      if (result == TusUploadState.paused) {
        _set(ReelComposerStage.paused);
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

      final readyAssetId = await _waitForReadyAsset(
        session.assetId,
        generation,
      );
      if (!_isCurrent(generation)) return;
      if (readyAssetId == null) {
        _set(ReelComposerStage.failed, error: reelProcessingFailureMessage);
        return;
      }

      await _publishReadyReel(readyAssetId, request, generation);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final failedStage = _stage;
      _debugLogReelPublishFailure(error, failedStage);
      _set(
        ReelComposerStage.failed,
        error: mapReelPublishError(error, failedStage),
      );
    } finally {
      _running = false;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<TusUploadState> _upload(TusUploadClient tus, int generation) async {
    await _progressSubscription?.cancel();
    _progressSubscription = tus.progress.listen((progress) {
      if (!_isCurrent(generation)) return;
      _progress = progress.fraction;
      notifyListeners();
    });
    try {
      return await tus.start();
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  void pauseUpload() {
    if (_disposed || _stage != ReelComposerStage.uploading) return;
    _tus?.pause();
  }

  Future<void> resumeUpload() async {
    if (_disposed ||
        _running ||
        _tus == null ||
        _stage != ReelComposerStage.paused) {
      return;
    }
    _running = true;
    final generation = ++_generation;
    try {
      _set(ReelComposerStage.uploading);
      final result = await _upload(_tus!, generation);
      if (!_isCurrent(generation)) return;
      if (result == TusUploadState.cancelled) {
        _set(ReelComposerStage.cancelled);
        return;
      }
      if (result == TusUploadState.paused) {
        _set(ReelComposerStage.paused);
        return;
      }
      if (result != TusUploadState.completed) {
        _set(ReelComposerStage.failed, error: reelUploadFailureMessage);
        return;
      }
      final assetId = _assetId ?? _tus?.assetId;
      final request = _pendingPublishRequest;
      if (assetId == null || request == null) {
        _set(ReelComposerStage.failed, error: reelUploadFailureMessage);
        return;
      }
      _set(ReelComposerStage.processing, progress: 1);
      final readyAssetId = await _waitForReadyAsset(assetId, generation);
      if (!_isCurrent(generation)) return;
      if (readyAssetId == null) {
        _set(ReelComposerStage.failed, error: reelProcessingFailureMessage);
        return;
      }
      await _publishReadyReel(readyAssetId, request, generation);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final failedStage = _stage;
      _debugLogReelPublishFailure(error, failedStage);
      _set(
        ReelComposerStage.failed,
        error: mapReelPublishError(error, failedStage),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _publishReadyReel(
    int readyAssetId,
    _ReelPublishRequest request,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    _set(ReelComposerStage.publishing, progress: 1);
    final reelId = await api.publishReel(
      assetId: readyAssetId,
      caption: request.caption,
      audience: request.audience,
      commentsEnabled: request.commentsEnabled,
      sharingEnabled: request.sharingEnabled,
      reelStyle: request.reelStyle,
      idempotencyKey: idempotencyKey,
    );
    if (!_isCurrent(generation)) return;
    _publishedReelId = reelId;
    _set(ReelComposerStage.published);
  }

  Future<int?> _waitForReadyAsset(int assetId, int generation) async {
    const attempts = 30;
    for (var i = 0; i < attempts; i++) {
      if (!_isCurrent(generation)) return null;
      final status = (await api.pollStatus(assetId)).trim().toLowerCase();
      if (!_isCurrent(generation)) return null;
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
    if (!canCancel) return;
    _generation++;
    _preparationCancel?.cancel();
    _tus?.cancel();
    _set(ReelComposerStage.cancelled);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _preparationCancel?.cancel();
    unawaited(_progressSubscription?.cancel());
    _tus?.cancel();
    _tus?.dispose();
    super.dispose();
  }
}

class _ReelPublishRequest {
  const _ReelPublishRequest({
    required this.caption,
    required this.audience,
    required this.commentsEnabled,
    required this.sharingEnabled,
    required this.reelStyle,
  });

  final String caption;
  final String audience;
  final bool commentsEnabled;
  final bool sharingEnabled;
  final Map<String, dynamic>? reelStyle;
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
  if (stage == ReelComposerStage.preparing) {
    return 'تعذر تجهيز الفيديو. بقيت تعديلاتك محفوظة هنا؛ حاول مرة أخرى.';
  }
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
