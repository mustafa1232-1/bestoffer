import 'dart:async';

/// Coalesces read cursors; an outage must never become an unbounded retry loop.
class SocialReadReceiptQueue {
  SocialReadReceiptQueue({required this.send, required this.canSend});

  final Future<int> Function(int messageId) send;
  final bool Function() canSend;
  int _pending = 0;
  int _acknowledged = 0;
  int _failures = 0;
  bool _busy = false;
  bool _disposed = false;
  Timer? _retry;

  void acknowledge(int messageId) {
    if (messageId > _acknowledged) _acknowledged = messageId;
  }

  void request(int messageId) {
    if (_disposed || messageId <= _acknowledged) return;
    if (messageId > _pending) {
      _pending = messageId;
      // A new message gets a fresh bounded retry budget.
      _failures = 0;
    }
    if (_retry == null) unawaited(_flush());
  }

  void pause() {
    _retry?.cancel();
    _retry = null;
  }

  void resume() {
    if (_disposed) return;
    _failures = 0;
    if (_retry == null) unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_disposed ||
        _busy ||
        _failures >= 4 ||
        _pending <= _acknowledged ||
        !canSend()) {
      return;
    }
    _busy = true;
    final sent = _pending;
    try {
      final acknowledged = await send(sent);
      if (_disposed) return;
      // A response that made no progress also needs backoff.
      if (acknowledged < sent) throw StateError('Read cursor did not advance');
      acknowledge(acknowledged);
      _failures = 0;
    } catch (_) {
      _failures++;
    } finally {
      _busy = false;
      if (!_disposed &&
          _pending > _acknowledged &&
          _failures < 4 &&
          canSend()) {
        _retry = Timer(
          _failures == 0
              ? Duration.zero
              : Duration(seconds: 1 << (_failures - 1)),
          () {
            _retry = null;
            unawaited(_flush());
          },
        );
      }
    }
  }

  void dispose() {
    _disposed = true;
    pause();
  }
}
