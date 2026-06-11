import 'package:dio/dio.dart';

/// يحلل حمولة أخطاء التحقق القادمة من الـ API إلى بنية ثابتة يمكن ربطها
/// بالحقول داخل الواجهة بدون أن تعتمد كل شاشة على شكل response مختلف.
class ParsedBackendFieldErrors {
  final Map<String, String?> fieldCodes;
  final String? formCode;
  final String? messageCode;
  final String? requestId;

  const ParsedBackendFieldErrors({
    this.fieldCodes = const <String, String?>{},
    this.formCode,
    this.messageCode,
    this.requestId,
  });

  bool get hasFieldErrors => fieldCodes.isNotEmpty;

  bool get hasAnyErrors =>
      fieldCodes.isNotEmpty ||
      (formCode != null && formCode!.isNotEmpty) ||
      (messageCode != null && messageCode!.isNotEmpty);

  String? codeFor(String field) => fieldCodes[field];
}

/// يدعم:
/// - `fields: ["phone", "pin"]`
/// - `fields: { "phone": "PHONE_EXISTS", "_form": "ADDRESS_INVALID" }`
/// - `details.fields` عندما يعيدها الباكند داخل details فقط.
ParsedBackendFieldErrors parseBackendFieldErrors(Object? source) {
  final data = source is DioException ? source.response?.data : source;
  if (data is! Map) {
    return const ParsedBackendFieldErrors();
  }

  final normalized = Map<String, dynamic>.from(data);
  final details = normalized['details'];
  final fieldsRaw = normalized['fields'] ?? (details is Map ? details['fields'] : null);
  final messageCode = _normalizeCode(normalized['message']);
  final requestId = _normalizeCode(normalized['requestId']);

  final fieldCodes = <String, String?>{};
  String? formCode;

  if (fieldsRaw is List) {
    for (final rawField in fieldsRaw) {
      final field = _normalizeCode(rawField);
      if (field == null) continue;
      fieldCodes[field] = null;
    }
  } else if (fieldsRaw is Map) {
    for (final entry in fieldsRaw.entries) {
      final field = _normalizeCode(entry.key);
      if (field == null) continue;
      final code = _normalizeCode(entry.value);
      if (field == '_FORM' || field == '_form') {
        formCode = code ?? messageCode;
      } else {
        fieldCodes[field] = code;
      }
    }
  } else {
    final loneField = _normalizeCode(fieldsRaw);
    if (loneField != null) {
      fieldCodes[loneField] = null;
    }
  }

  return ParsedBackendFieldErrors(
    fieldCodes: fieldCodes,
    formCode: formCode,
    messageCode: messageCode,
    requestId: requestId,
  );
}

String? _normalizeCode(Object? value) {
  final raw = '$value'.trim();
  if (raw.isEmpty || raw == 'null') return null;
  return raw;
}
