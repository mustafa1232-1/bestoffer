import 'dart:async';
import 'dart:math' as math;

/// A minimal, dependency-light resumable (tus) upload client for direct
/// Flutter → Cloudflare Stream uploads (§5).
///
/// The video bytes go straight to Cloudflare; the backend never sees the body.
/// Transport is abstracted behind [TusTransport] so tests use a fake and never
/// touch the network. Only safe session info is persisted (never any Cloudflare
/// secret — the client only ever holds a one-time upload URL provisioned by the
/// backend).

/// Result of a PATCH/HEAD against the tus endpoint.
class TusTransportResult {
  const TusTransportResult({required this.offset, this.completed = false});

  /// The server's authoritative Upload-Offset after the operation.
  final int offset;

  /// True when the server reports the upload finished.
  final bool completed;
}

/// Thrown when the upload URL is no longer valid (expired / 410 / 404).
class TusExpiredUploadException implements Exception {
  const TusExpiredUploadException([this.message = 'upload url expired']);
  final String message;
  @override
  String toString() => 'TusExpiredUploadException($message)';
}

/// Transport seam. Production wires this to Dio/HTTP; tests use a fake.
abstract class TusTransport {
  /// HEAD → returns the current server offset (tus `Upload-Offset`).
  Future<int> head(String uploadUrl);

  /// PATCH a chunk starting at [offset]; returns the new server offset.
  Future<TusTransportResult> patch(
    String uploadUrl, {
    required int offset,
    required int length,
    required int total,
  });
}

enum TusUploadState { idle, uploading, paused, completed, cancelled, failed }

/// Persisted, secret-free snapshot of an in-flight upload so it survives an app
/// restart (§5 "app restart recovery").
class TusSessionSnapshot {
  const TusSessionSnapshot({
    required this.uploadUrl,
    required this.totalBytes,
    required this.offset,
    required this.assetId,
  });

  final String uploadUrl;
  final int totalBytes;
  final int offset;
  final int assetId;

  Map<String, dynamic> toJson() => {
        'uploadUrl': uploadUrl,
        'totalBytes': totalBytes,
        'offset': offset,
        'assetId': assetId,
      };

  factory TusSessionSnapshot.fromJson(Map<String, dynamic> j) =>
      TusSessionSnapshot(
        uploadUrl: j['uploadUrl'] as String,
        totalBytes: (j['totalBytes'] as num).toInt(),
        offset: (j['offset'] as num).toInt(),
        assetId: (j['assetId'] as num).toInt(),
      );
}

class TusProgress {
  const TusProgress({
    required this.state,
    required this.uploaded,
    required this.total,
  });

  final TusUploadState state;
  final int uploaded;
  final int total;

  double get fraction => total <= 0 ? 0 : (uploaded / total).clamp(0.0, 1.0);
}

class TusUploadClient {
  TusUploadClient({
    required this.transport,
    required this.uploadUrl,
    required this.totalBytes,
    required this.assetId,
    this.chunkSize = 8 * 1024 * 1024,
    this.maxRetries = 5,
    int initialOffset = 0,
    Future<void> Function(TusSessionSnapshot snapshot)? persist,
  })  : _offset = initialOffset,
        _persist = persist;

  final TusTransport transport;
  final String uploadUrl;
  final int totalBytes;
  final int assetId;
  final int chunkSize;
  final int maxRetries;
  final Future<void> Function(TusSessionSnapshot snapshot)? _persist;

  final _progress = StreamController<TusProgress>.broadcast();
  Stream<TusProgress> get progress => _progress.stream;

  int _offset;
  int _attempt = 0;
  TusUploadState _state = TusUploadState.idle;
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  int get offset => _offset;
  TusUploadState get state => _state;

  void _emit() {
    if (_progress.isClosed) return;
    _progress.add(
      TusProgress(state: _state, uploaded: _offset, total: totalBytes),
    );
  }

  Future<void> _snapshot() async {
    await _persist?.call(
      TusSessionSnapshot(
        uploadUrl: uploadUrl,
        totalBytes: totalBytes,
        offset: _offset,
        assetId: assetId,
      ),
    );
  }

  void pause() {
    if (_state == TusUploadState.uploading) _pauseRequested = true;
  }

  void cancel() {
    _cancelRequested = true;
  }

  /// Starts (or resumes) the upload. Idempotent: calling it again after a pause
  /// resumes from the server's authoritative offset.
  Future<TusUploadState> start() async {
    if (_state == TusUploadState.completed ||
        _state == TusUploadState.cancelled) {
      return _state;
    }
    // Pause is per-run and cleared on (re)start; cancel is sticky — a cancel
    // requested before start() must still take effect.
    _pauseRequested = false;
    _state = TusUploadState.uploading;
    _emit();

    try {
      // Always reconcile with the server offset first (recovers from restart /
      // offset mismatch / duplicate completion).
      _offset = await _headWithRetry();
      if (_offset >= totalBytes) {
        return _finish();
      }

      while (_offset < totalBytes) {
        if (_cancelRequested) {
          _state = TusUploadState.cancelled;
          _emit();
          return _state;
        }
        if (_pauseRequested) {
          _state = TusUploadState.paused;
          _emit();
          return _state;
        }

        final length = math.min(chunkSize, totalBytes - _offset);
        final result = await _patchWithRetry(_offset, length);
        // Trust the server offset, not our local arithmetic (handles partial
        // writes / offset mismatch).
        _offset = result.offset;
        await _snapshot();
        _emit();
        if (result.completed || _offset >= totalBytes) {
          return _finish();
        }
      }
      return _finish();
    } on TusExpiredUploadException {
      _state = TusUploadState.failed;
      _emit();
      rethrow;
    } catch (_) {
      _state = TusUploadState.failed;
      _emit();
      return _state;
    }
  }

  TusUploadState _finish() {
    _state = TusUploadState.completed;
    _offset = totalBytes;
    _emit();
    return _state;
  }

  Future<int> _headWithRetry() async {
    _attempt = 0;
    while (true) {
      try {
        return await transport.head(uploadUrl);
      } on TusExpiredUploadException {
        rethrow;
      } catch (_) {
        if (!_shouldRetry()) rethrow;
        await _backoff();
      }
    }
  }

  Future<TusTransportResult> _patchWithRetry(int offset, int length) async {
    _attempt = 0;
    while (true) {
      try {
        return await transport.patch(
          uploadUrl,
          offset: offset,
          length: length,
          total: totalBytes,
        );
      } on TusExpiredUploadException {
        rethrow;
      } catch (_) {
        if (!_shouldRetry()) rethrow;
        await _backoff();
        // Re-sync offset before retrying the chunk.
        offset = await transport.head(uploadUrl);
        _offset = offset;
      }
    }
  }

  bool _shouldRetry() => ++_attempt <= maxRetries;

  Future<void> _backoff() async {
    // Bounded exponential backoff (cap ~8s). Deterministic (no jitter) so tests
    // stay stable; real jitter can be layered by the transport if desired.
    final ms = math.min(8000, 200 * (1 << (_attempt - 1)));
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> dispose() async {
    await _progress.close();
  }
}
