import 'package:dio/dio.dart';

/// The backend code returned when a scoped-story request is rejected by the
/// fail-closed gate.
const String kStoryScopeUnavailableCode = 'STORY_AUDIENCE_SCOPE_NOT_AVAILABLE';

/// True when [error] is the backend's 409 `STORY_AUDIENCE_SCOPE_NOT_AVAILABLE`
/// response. Matches on the structured code (not only the HTTP status).
bool isStoryScopeUnavailableError(Object? error) {
  if (error is! DioException) return false;
  final response = error.response;
  final data = response?.data;
  final code = data is Map
      ? (data['message'] ?? data['code'] ?? (data['error'] is Map ? data['error']['code'] : null))
      : null;
  return '$code' == kStoryScopeUnavailableCode;
}

/// Extracts the safe localized (ar) message the backend supplied, if any.
String? storyScopeUnavailableMessage(Object? error, {String locale = 'ar'}) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final details = data['details'];
  if (details is Map && details['messages'] is Map) {
    final msg = details['messages'][locale];
    if (msg is String && msg.trim().isNotEmpty) return msg;
  }
  return null;
}
