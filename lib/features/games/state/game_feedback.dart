import 'dart:async';

/// Fires a haptic (or other platform feedback) without ever letting it affect
/// game logic: feedback is best-effort and may be unavailable (web, tests,
/// devices without a vibration motor).
void gameFeedback(Future<void> Function() effect) {
  try {
    unawaited(effect().catchError((Object _) {}));
  } catch (_) {
    // Platform channel not ready; the tap itself already succeeded.
  }
}
