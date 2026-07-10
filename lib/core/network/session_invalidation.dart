import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Broadcasts a "the session is terminally invalid" event (confirmed
/// INVALID_TOKEN / NO_TOKEN / INVALID_REFRESH_TOKEN that cannot be refreshed).
///
/// The Dio interceptor bumps this once when it detects a terminal auth failure;
/// [AuthController] listens and drops the app to guest/login. Using a tiny
/// broadcast avoids a circular dependency between the network layer and auth.
class SessionInvalidationBus extends ChangeNotifier {
  SessionInvalidationBus._();

  static final SessionInvalidationBus instance = SessionInvalidationBus._();

  int _tick = 0;
  int get tick => _tick;

  /// Signals that the session is terminally invalid. Idempotent per burst is not
  /// required — listeners simply react to the latest tick.
  void invalidate() {
    _tick++;
    notifyListeners();
  }
}

/// True for a 401 whose body indicates a terminal auth failure that a token
/// refresh cannot fix.
bool isTerminalAuthError(DioException error) {
  if (error.response?.statusCode != 401) return false;
  final data = error.response?.data;
  final raw = data is Map ? (data['message'] ?? data['code']) : data;
  final code = '$raw'.trim().toUpperCase();
  return code == 'INVALID_TOKEN' ||
      code == 'NO_TOKEN' ||
      code == 'INVALID_REFRESH_TOKEN';
}
