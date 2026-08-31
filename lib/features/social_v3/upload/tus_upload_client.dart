import 'dart:async';
import 'dart:math' as math;

/// A minimal, dependency-light resumable (tus) upload client for direct
/// Flutter → Cloudflare Stream uploads.
///
/// The video bytes go straight to Cloudflare; the backend never sees the body.
/// Transport is abstracted behind [TusTransport] so tests use a fake and never
/// touch the network. Only safe session info is persisted (never any Cloudflare
/// secret — the client only ever holds a one-time upload URL provisioned by the
/// backend).

class TusTransportResult {
  const TusTransportResult({required this.offset, this.completed = false});

  final int offset;
  final bool completed;
}

class TusExpiredUploadException implements Exception {
  const TusExpiredUploadException([this.message = 'upload url expired']);
  final String message;
  @override
  String toString() => 'TusExpiredUploadException($message)';
}

abstract class TusTransport {
  Future<int> head(String uploadUrl);

  Future<TusTransportResult> patch(
    String uploadUrl, {
    required int offset,
    required int length,
    required int total,
  });
}

enum TusUploadState { idle, uploading, paused, completed, cancelled, failed }

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
    this.chunkSize = 4 * 1024 * 1024,
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
  bool _disposed = false;

  int get offset => _offset;
  TusUploadState get state => _state;

  void _emit() {
    if (_disposed || _progress.isClosed) return;
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

  Future<TusUploadState> start() async {
    if (_disposed) return TusUploadState.cancelled;
    if (_state == TusUploadState.completed ||
        _state == TusUploadState.cancelled) {
      return _state;
    }
    if (totalBytes <= 0 || chunkSize <= 0) {
      _state = TusUploadState.failed;
      _emit();
      return _state;
    }

    _pauseRequested = false;
    _state = TusUploadState.uploading;
    _emit();

    try {
      _offset = (await _headWithRetry()).clamp(0, totalBytes).toInt();
      await _snapshot();
      _emit();
      if (_offset >= totalBytes) {
        return _finish();
      }

      while (_offset < totalBytes) {
        if (_cancelRequested || _disposed) {
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
        _offset = result.offset.clamp(0, totalBytes).toInt();
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
      if (_cancelRequested || _disposed) return _offset;
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
    var nextOffset = offset;
    var nextLength = length;
    while (true) {
      if (_cancelRequested || _disposed) {
        return TusTransportResult(offset: nextOffset);
      }
      try {
        return await transport.patch(
          uploadUrl,
          offset: nextOffset,
          length: nextLength,
          total: totalBytes,
        );
      } on TusExpiredUploadException {
        rethrow;
      } catch (_) {
        if (!_shouldRetry()) rethrow;
        await _backoff();
        nextOffset = (await transport.head(uploadUrl))
            .clamp(0, totalBytes)
            .toInt();
        _offset = nextOffset;
        await _snapshot();
        _emit();
        if (nextOffset >= totalBytes) {
          return TusTransportResult(offset: totalBytes, completed: true);
        }
        nextLength = math.min(chunkSize, totalBytes - nextOffset);
      }
    }
  }

  bool _shouldRetry() => ++_attempt <= maxRetries;

  Future<void> _backoff() async {
    final ms = math.min(8000, 200 * (1 << (_attempt - 1)));
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelRequested = true;
    await _progress.close();
  }
}
