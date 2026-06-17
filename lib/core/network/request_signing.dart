import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

const String requestSigningKeyIdStorageKey = 'request_signing_key_id';
const String requestSigningSecretStorageKey = 'request_signing_secret';
const String requestSigningIssuedAtStorageKey = 'request_signing_issued_at';
const String requestSigningExpiresAtStorageKey = 'request_signing_expires_at';
const String requestSigningAlgorithmStorageKey = 'request_signing_algorithm';
const String requestSigningRefreshWindowStorageKey =
    'request_signing_refresh_window_sec';

class RequestSigningMaterial {
  const RequestSigningMaterial({
    required this.keyId,
    required this.secret,
    required this.issuedAt,
    required this.expiresAt,
    required this.algorithm,
    required this.refreshWindowSec,
  });

  final String keyId;
  final String secret;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String algorithm;
  final int refreshWindowSec;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get shouldRefreshSoon =>
      DateTime.now().isAfter(
        expiresAt.subtract(Duration(seconds: refreshWindowSec)),
      );

  Map<String, String> toStorageMap() {
    return <String, String>{
      requestSigningKeyIdStorageKey: keyId,
      requestSigningSecretStorageKey: secret,
      requestSigningIssuedAtStorageKey: issuedAt.toUtc().toIso8601String(),
      requestSigningExpiresAtStorageKey: expiresAt.toUtc().toIso8601String(),
      requestSigningAlgorithmStorageKey: algorithm,
      requestSigningRefreshWindowStorageKey: '$refreshWindowSec',
    };
  }

  static RequestSigningMaterial? fromStorageMap(Map<String, String?> map) {
    final keyId = (map[requestSigningKeyIdStorageKey] ?? '').trim();
    final secret = (map[requestSigningSecretStorageKey] ?? '').trim();
    final issuedAtRaw = (map[requestSigningIssuedAtStorageKey] ?? '').trim();
    final expiresAtRaw = (map[requestSigningExpiresAtStorageKey] ?? '').trim();
    final algorithm =
        (map[requestSigningAlgorithmStorageKey] ?? '').trim().toLowerCase();
    final refreshWindow = int.tryParse(
      (map[requestSigningRefreshWindowStorageKey] ?? '').trim(),
    );

    final issuedAt = DateTime.tryParse(issuedAtRaw)?.toUtc();
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (keyId.isEmpty ||
        secret.isEmpty ||
        issuedAt == null ||
        expiresAt == null) {
      return null;
    }

    return RequestSigningMaterial(
      keyId: keyId,
      secret: secret,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      algorithm: algorithm.isEmpty ? 'hmac-sha256' : algorithm,
      refreshWindowSec: refreshWindow == null || refreshWindow < 15
          ? 120
          : refreshWindow,
    );
  }

  static RequestSigningMaterial fromResponse(Map<String, dynamic> json) {
    final keyId = '${json['keyId'] ?? ''}'.trim();
    final secret = '${json['signingSecret'] ?? ''}'.trim();
    final issuedAt =
        DateTime.tryParse('${json['issuedAt'] ?? ''}')?.toUtc() ??
        DateTime.now().toUtc();
    final expiresIn = int.tryParse('${json['expiresIn'] ?? ''}') ?? 900;
    final refreshWindow =
        int.tryParse('${json['refreshWindowSec'] ?? ''}') ?? 120;
    return RequestSigningMaterial(
      keyId: keyId,
      secret: secret,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(Duration(seconds: expiresIn)),
      algorithm: '${json['algorithm'] ?? 'hmac-sha256'}'.trim().toLowerCase(),
      refreshWindowSec: refreshWindow < 15 ? 120 : refreshWindow,
    );
  }
}

bool requiresRequestSigning({
  required String method,
  required String path,
}) {
  final normalizedMethod = method.trim().toUpperCase();
  final normalizedPath = normalizePathForSigning(path);

  bool matches(RegExp pattern) => pattern.hasMatch(normalizedPath);

  if (normalizedMethod == 'PATCH' && normalizedPath == '/api/auth/account') {
    return true;
  }
  if (normalizedMethod == 'POST' &&
      normalizedPath == '/api/owner/settlements/request') {
    return true;
  }
  if ((normalizedMethod == 'POST' || normalizedMethod == 'PATCH') &&
      matches(
        RegExp(r'^/api/merchant/payment-requests(?:/\d+)?(?:/(confirm-received|report-issue))?$'),
      )) {
    return true;
  }
  if (normalizedMethod == 'POST' &&
      matches(
        RegExp(
          r'^/api/accountant/(opening-balance|expenses|pending-delivery-settlements/\d+/confirm|payroll/batches/\d+/acknowledge|payroll/items/\d+/pay)$',
        ),
      )) {
    return true;
  }
  if ((normalizedMethod == 'POST' || normalizedMethod == 'PUT' || normalizedMethod == 'PATCH') &&
      matches(
        RegExp(
          r'^/api/admin/(payment-requests/\d+/(mark-received|approve|assign|mark-paid|return-for-revision|reject)|merchants/\d+/(billing-profile|app-payables/adjustment)|customer-reliability/policy|delivery-dispatch/policy)$',
        ),
      )) {
    return true;
  }
  return false;
}

String normalizePathForSigning(String path) {
  final trimmed = path.trim();
  final withoutQuery = trimmed.split('?').first.trim();
  if (withoutQuery.startsWith('/api/v1/')) {
    return withoutQuery.replaceFirst('/api/v1/', '/api/');
  }
  if (withoutQuery == '/api/v1') {
    return '/api';
  }
  return withoutQuery.isEmpty
      ? '/'
      : withoutQuery.startsWith('/')
          ? withoutQuery
          : '/$withoutQuery';
}

Object? _stableJsonValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return <String, Object?>{
      for (final entry in entries) entry.key.toString(): _stableJsonValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_stableJsonValue).toList(growable: false);
  }
  return value;
}

String stableJsonEncode(Object? value) {
  if (value == null || value == '') return '';
  if (value is String) return value;
  return jsonEncode(_stableJsonValue(value));
}

String buildRequestBodyHash(Object? body) {
  return sha256.convert(utf8.encode(stableJsonEncode(body))).toString();
}

String buildRequestSigningCanonical({
  required String method,
  required String path,
  required String timestamp,
  required String nonce,
  required String sessionId,
  required String deviceFingerprint,
  required String bodyHash,
}) {
  return <String>[
    method.trim().toUpperCase(),
    normalizePathForSigning(path),
    timestamp.trim(),
    nonce.trim(),
    sessionId.trim(),
    deviceFingerprint.trim(),
    bodyHash.trim(),
  ].join('\n');
}

String buildRequestSignature({
  required String secret,
  required String canonical,
}) {
  return Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(canonical)).bytes.base64Url;
}

extension on List<int> {
  String get base64Url {
    return base64UrlEncode(this).replaceAll('=', '');
  }
}

String resolveRequestPath(RequestOptions options) {
  final uri = options.uri;
  final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  return path;
}
