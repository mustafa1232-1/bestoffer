import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Broadcasts a "the session is terminally invalid" event.
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
  /// required - listeners simply react to the latest tick.
  void invalidate() {
    _tick++;
    notifyListeners();
  }
}

/// True for a 401 that should invalidate the current authenticated session.
///
/// Anonymous/public requests are excluded so login/register/guest flows do not
/// surface a false "session expired" state when they receive a 401 for reasons
/// unrelated to a logged-in session.
bool isTerminalAuthError(DioException error) {
  if (error.response?.statusCode != 401) return false;

  if (isSessionInvalidationExemptRequest(error.requestOptions)) {
    return false;
  }

  final request = error.requestOptions;
  final code = _extractAuthCode(error.response?.data);
  final hasBearer = _hasBearerAuthorization(request);

  if (code == 'INVALID_CREDENTIALS') return false;
  if (hasBearer) return true;
  return false;
}

bool isSessionInvalidationExemptRequest(RequestOptions request) {
  final path = _normalizedPath(request.path);
  final hasBearer = _hasBearerAuthorization(request);

  if (_isAnonymousAuthPath(path)) return true;
  if (_isAnonymousServiceRegistrationPath(path)) return true;
  if (path == '/api/realtime/token' && !hasBearer) return true;
  if (path == '/api/auth/refresh' && !_hasRefreshToken(request)) return true;
  if (_isPublicPath(path) && !hasBearer) return true;
  if (request.extra['skipAuth'] == true && !hasBearer) return true;
  return false;
}

bool _isAnonymousAuthPath(String path) {
  return switch (path) {
    '/api/auth/login' => true,
    '/api/auth/register' => true,
    '/api/auth/register-with-card' => true,
    '/api/auth/owner/register' => true,
    '/api/taxi/captain/register' => true,
    '/api/auth/ocr/extract-residence-card' => true,
    '/api/auth/logout' => true,
    '/api/auth/logout-all' => true,
    _ => false,
  };
}

bool _isAnonymousServiceRegistrationPath(String path) {
  return switch (path) {
    '/api/services/provider/register' => true,
    '/api/services/provider/subscription/status' => true,
    _ when path.startsWith('/api/services/provider/subscription/requests/') =>
      true,
    _ => false,
  };
}

bool _isPublicPath(String path) {
  return path.contains('/public/');
}

String _normalizedPath(String path) {
  final trimmed = path.trim().toLowerCase();
  if (trimmed.isEmpty) return '/';
  return trimmed.split('?').first;
}

bool _hasBearerAuthorization(RequestOptions request) {
  final header =
      request.headers['Authorization'] ?? request.headers['authorization'];
  final raw = '$header'.trim();
  if (raw.isEmpty) return false;
  const prefix = 'Bearer ';
  if (!raw.toLowerCase().startsWith(prefix.toLowerCase())) return false;
  final token = raw.substring(prefix.length).trim();
  return token.isNotEmpty;
}

bool _hasRefreshToken(RequestOptions request) {
  final body = request.data;
  if (body is Map) {
    final raw = body['refreshToken'] ?? body['refresh_token'];
    final text = '$raw'.trim();
    return text.isNotEmpty && text.toLowerCase() != 'null';
  }
  return false;
}

String _extractAuthCode(dynamic data) {
  final raw = data is Map ? (data['message'] ?? data['code']) : data;
  return '$raw'.trim().toUpperCase();
}
