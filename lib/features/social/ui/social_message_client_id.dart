import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/files/local_media_file.dart';

dynamic _normalizeCanonicalValue(dynamic value) {
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) => MapEntry(
            entry.key.toString(),
            _normalizeCanonicalValue(entry.value),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      for (final entry in entries) entry.key: entry.value,
    };
  }
  if (value is Iterable) {
    return value.map(_normalizeCanonicalValue).toList(growable: false);
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is num || value is bool || value == null) {
    return value;
  }
  return value.toString();
}

String buildSocialMessageFingerprint({
  required String scopeKey,
  required String body,
  int? replyToMessageId,
  LocalMediaFile? attachmentFile,
  int? attachmentDurationMs,
  String? sharedEntityType,
  int? sharedEntityId,
  Map<String, dynamic>? sharedSnapshot,
}) {
  final attachment = attachmentFile == null
      ? null
      : <String, dynamic>{
          'name': attachmentFile.name.trim(),
          'path': (attachmentFile.path ?? '').trim(),
          'mimeType': (attachmentFile.mimeType ?? '').trim(),
          'sizeBytes': attachmentFile.sizeBytes,
        };
  attachment?.removeWhere((_, value) => value == null || value == '');
  final payload = <String, dynamic>{
    'scopeKey': scopeKey.trim(),
    'body': body.trim(),
    'replyToMessageId': replyToMessageId,
    'attachmentDurationMs': attachmentDurationMs,
    'attachment': attachment,
    'sharedEntityType': (sharedEntityType ?? '').trim().toLowerCase(),
    'sharedEntityId': sharedEntityId,
    'sharedSnapshot': sharedSnapshot,
  }..removeWhere((_, value) => value == null || value == '');
  final canonical = jsonEncode(_normalizeCanonicalValue(payload));
  return sha256.convert(utf8.encode(canonical)).toString();
}

String buildSocialMessageClientId({
  required String scopeKey,
  required String body,
  int? replyToMessageId,
  LocalMediaFile? attachmentFile,
  int? attachmentDurationMs,
  String? sharedEntityType,
  int? sharedEntityId,
  Map<String, dynamic>? sharedSnapshot,
}) {
  final fingerprint = buildSocialMessageFingerprint(
    scopeKey: scopeKey,
    body: body,
    replyToMessageId: replyToMessageId,
    attachmentFile: attachmentFile,
    attachmentDurationMs: attachmentDurationMs,
    sharedEntityType: sharedEntityType,
    sharedEntityId: sharedEntityId,
    sharedSnapshot: sharedSnapshot,
  );
  return 'msg_${fingerprint.substring(0, 24)}';
}
