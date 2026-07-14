import 'package:flutter/foundation.dart';

import '../pickers/social_media_picker_v3.dart';
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
    required String idempotencyKey,
  });
}

/// Factory for a [TusUploadClient] given an upload URL + size (injected for tests).
typedef TusClientFactory = TusUploadClient Function({
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
    Duration pollInterval = const Duration(seconds: 2),
    int maxPolls = 30,
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
        _set(ReelComposerStage.failed, error: 'UPLOAD_FAILED');
        return;
      }

      // Processing — the backend/webhook/reconciliation own the terminal state.
      _set(ReelComposerStage.processing, progress: 1);
      final ready = await _awaitReady(
        session.assetId,
        pollInterval: pollInterval,
        maxPolls: maxPolls,
      );
      if (!ready) {
        _set(ReelComposerStage.failed, error: 'PROCESSING_TIMEOUT');
        return;
      }

      final reelId = await api.publishReel(
        assetId: session.assetId,
        caption: caption,
        audience: audience,
        commentsEnabled: commentsEnabled,
        sharingEnabled: sharingEnabled,
        idempotencyKey: idempotencyKey,
      );
      _publishedReelId = reelId;
      _set(ReelComposerStage.published);
    } catch (error) {
      _set(ReelComposerStage.failed, error: '$error');
    }
  }

  Future<bool> _awaitReady(
    int assetId, {
    required Duration pollInterval,
    required int maxPolls,
  }) async {
    for (var i = 0; i < maxPolls; i++) {
      final status = (await api.pollStatus(assetId)).toLowerCase();
      if (status == 'ready' || status == 'published') return true;
      if (status == 'failed' || status == 'rejected') return false;
      if (i < maxPolls - 1) await Future<void>.delayed(pollInterval);
    }
    return false;
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
