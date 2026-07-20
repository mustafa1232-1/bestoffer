import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum SessionRecoveryDecision {
  recoverable,
  staleFailure,
  needsRecovery,
  userRequestedLogout,
}

typedef SessionInvalidationDecision = SessionRecoveryDecision;

/// Broadcasts non-destructive session recovery hints.
///
/// This bus must never be used to clear auth storage or navigate to login.
class SessionRecoveryBus extends ChangeNotifier {
  SessionRecoveryBus._();

  static final SessionRecoveryBus instance = SessionRecoveryBus._();

  int _tick = 0;
  int get tick => _tick;

  void requestRecovery() {
    _tick++;
    notifyListeners();
  }

  @Deprecated('Use requestRecovery(); this no longer means logout.')
  void invalidate() {}
}

typedef SessionInvalidationBus = SessionRecoveryBus;

/// Coordinates auth recovery decisions. It does not own logout and never clears
/// user/session storage for server or network errors.
class SessionRecoveryCoordinator {
  SessionRecoveryCoordinator._();

  static final SessionRecoveryCoordinator instance =
      SessionRecoveryCoordinator._();

  final SessionRecoveryBus bus = SessionRecoveryBus.instance;
  Future<void>? _recoveryInFlight;
  final Map<String, Future<String?>> _refreshFutures =
      <String, Future<String?>>{};
  final Map<String, Future<String?>> _sessionRecoveryFutures =
      <String, Future<String?>>{};
  bool _recoveryPending = false;

  bool get terminalInvalidated => false;
  bool get recoveryPending => _recoveryPending;

  SessionRecoveryDecision classify(
    DioException error, {
    String? expectedRefreshToken,
    String? currentRefreshToken,
  }) {
    if (error.response?.statusCode != 401) {
      return SessionRecoveryDecision.recoverable;
    }

    if (error.requestOptions.extra['skipTerminalSessionInvalidation'] == true) {
      return SessionRecoveryDecision.recoverable;
    }

    if (isSessionInvalidationExemptRequest(error.requestOptions)) {
      return SessionRecoveryDecision.recoverable;
    }

    final code = _extractAuthCode(error.response?.data);
    final hasBearer = _hasBearerAuthorization(error.requestOptions);
    if (!hasBearer) {
      return SessionRecoveryDecision.recoverable;
    }

    if (!isSessionAuthFailureCode(code)) {
      return SessionRecoveryDecision.recoverable;
    }

    if (expectedRefreshToken != null) {
      final expected = expectedRefreshToken.trim();
      final current = (currentRefreshToken ?? '').trim();
      if (expected.isNotEmpty && (current.isEmpty || expected != current)) {
        return SessionRecoveryDecision.staleFailure;
      }
    }

    if (isRecoverableSessionAuthCode(code)) {
      return SessionRecoveryDecision.needsRecovery;
    }

    return SessionRecoveryDecision.needsRecovery;
  }

  Future<void> runRecovery({required Future<void> Function() cleanup}) async {
    final inFlight = _recoveryInFlight;
    if (inFlight != null) return inFlight;

    final future = _runRecovery(cleanup);
    _recoveryInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_recoveryInFlight, future)) {
        _recoveryInFlight = null;
      }
    }
  }

  Future<String?> runRefreshOnce({
    required String key,
    required Future<String?> Function() task,
  }) {
    return _runStringOnce(_refreshFutures, key: key, task: task);
  }

  Future<String?> runSessionRecoveryOnce({
    required String key,
    required Future<String?> Function() task,
  }) {
    return _runStringOnce(_sessionRecoveryFutures, key: key, task: task);
  }

  @Deprecated('Use runRecovery(); automatic terminal logout is disabled.')
  Future<void> invalidateTerminalSession({
    required Future<void> Function() cleanup,
  }) => runRecovery(cleanup: () async {});

  void reset() {
    _recoveryPending = false;
    _recoveryInFlight = null;
    _refreshFutures.clear();
    _sessionRecoveryFutures.clear();
  }

  Future<String?> _runStringOnce(
    Map<String, Future<String?>> futures, {
    required String key,
    required Future<String?> Function() task,
  }) {
    final normalizedKey = key.trim().isEmpty ? 'default' : key.trim();
    final inFlight = futures[normalizedKey];
    if (inFlight != null) return inFlight;
    final future = task();
    futures[normalizedKey] = future;
    return future.whenComplete(() {
      if (identical(futures[normalizedKey], future)) {
        futures.remove(normalizedKey);
      }
    });
  }

  Future<void> _runRecovery(Future<void> Function() cleanup) async {
    _recoveryPending = true;
    try {
      await cleanup();
    } finally {
      bus.requestRecovery();
    }
  }
}

typedef SessionInvalidationCoordinator = SessionRecoveryCoordinator;

bool isTerminalAuthError(DioException error) {
  return false;
}

bool isRecoverableSessionAuthCode(String? code) {
  final normalized = code?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) return false;
  return normalized == 'INVALID_TOKEN' ||
      normalized == 'NO_TOKEN' ||
      normalized == 'INVALID_REFRESH_TOKEN' ||
      normalized == 'SESSION_RECOVERY_REQUIRED' ||
      normalized == 'TOKEN_EXPIRED' ||
      normalized == 'ACCESS_TOKEN_EXPIRED' ||
      normalized == 'SESSION_EXPIRED';
}

bool isTerminalSessionAuthCode(String? code) {
  final normalized = code?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) return false;
  return normalized == 'REFRESH_TOKEN_EXPIRED' ||
      normalized == 'REFRESH_TOKEN_REUSED' ||
      normalized == 'SESSION_REVOKED' ||
      normalized == 'DEVICE_BINDING_MISMATCH' ||
      normalized == 'APP_SURFACE_MISMATCH' ||
      normalized == 'JWT_SIGNATURE_INVALID' ||
      normalized == 'ACCOUNT_DISABLED';
}

bool isSessionAuthFailureCode(String? code) {
  return isRecoverableSessionAuthCode(code) || isTerminalSessionAuthCode(code);
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
