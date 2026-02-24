import 'dart:convert';

int parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? fallback;
  if (value is num) return value.toInt();
  return fallback;
}

double parseDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String parseString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final normalized = normalizeText(value.toString());
  return normalized.isEmpty ? fallback : normalized;
}

String? parseNullableString(dynamic value) {
  if (value == null) return null;
  final normalized = normalizeText(value.toString());
  if (normalized.isEmpty) return null;
  return normalized;
}

String normalizeText(String value) {
  if (value.isEmpty) return value;

  final cleaned = value.replaceAll('\uFFFD', '');
  if (!_looksMojibake(cleaned)) return cleaned;

  final repaired = _decodeLatin1AsUtf8(cleaned);
  final cleanedArabic = _arabicCount(cleaned);
  final repairedArabic = _arabicCount(repaired);

  if (repairedArabic > cleanedArabic) {
    return repaired;
  }

  return cleaned;
}

String _decodeLatin1AsUtf8(String value) {
  try {
    return utf8.decode(latin1.encode(value));
  } catch (_) {
    return value;
  }
}

bool _looksMojibake(String value) {
  const markers = <String>['Ø', 'Ù', 'Ú', 'Û', 'Ã', 'Ð', 'Ñ', 'Þ', 'Æ'];
  return markers.any(value.contains);
}

int _arabicCount(String value) {
  var count = 0;
  for (final code in value.runes) {
    if (code >= 0x0600 && code <= 0x06FF) {
      count++;
    }
  }
  return count;
}
