import 'dart:convert';

String normalizeNumericInput(String value) {
  return value
      .trim()
      .replaceAll(',', '')
      .replaceAll('،', '')
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAllMapped(
        RegExp(r'[\u0660-\u0669]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0660 + 0x30),
      )
      .replaceAllMapped(
        RegExp(r'[\u06F0-\u06F9]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x06F0 + 0x30),
      );
}

int? tryParseLocalizedInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = normalizeNumericInput(value.toString());
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

double? tryParseLocalizedDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  final text = normalizeNumericInput(value.toString());
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

int parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is String) return tryParseLocalizedInt(value) ?? fallback;
  if (value is num) return value.toInt();
  return fallback;
}

int? parseNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return tryParseLocalizedInt(text);
  }
  return null;
}

double parseDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return tryParseLocalizedDouble(value) ?? fallback;
  return fallback;
}

bool parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

DateTime? parseNullableDateTime(dynamic value) {
  if (value == null) return null;
  final text = parseString(value, fallback: '');
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
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
  if (!_looksMojibake(value) && !_looksMojibake(cleaned)) {
    return cleaned;
  }

  final candidates = <String>{value, cleaned};
  var current = value;
  for (var i = 0; i < 6; i++) {
    final repaired = _decodeWindows1252Utf8Pass(current);
    if (repaired == current) break;
    candidates.add(repaired);
    candidates.add(repaired.replaceAll('\uFFFD', ''));
    current = repaired;
  }

  var best = cleaned;
  var bestScore = _textQualityScore(best);
  for (final candidate in candidates) {
    final score = _textQualityScore(candidate);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }

  return best;
}

const Map<int, int> _cp1252ExtraRuneToByte = {
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

List<int> _encodeMixedWindows1252Like(String value) {
  final out = <int>[];
  for (final rune in value.runes) {
    if (rune <= 0x7F || (rune >= 0xA0 && rune <= 0xFF)) {
      out.add(rune);
      continue;
    }
    final mapped = _cp1252ExtraRuneToByte[rune];
    if (mapped != null) {
      out.add(mapped);
      continue;
    }
    out.addAll(utf8.encode(String.fromCharCode(rune)));
  }
  return out;
}

String _decodeWindows1252Utf8Pass(String value) {
  try {
    return utf8.decode(
      _encodeMixedWindows1252Like(value),
      allowMalformed: false,
    );
  } catch (_) {
    return value;
  }
}

bool _looksMojibake(String value) {
  return value.contains('\uFFFD') ||
      value.contains('\u00C3') ||
      value.contains('\u00C2') ||
      value.contains('\u00E2') ||
      value.contains('\u00C5') ||
      RegExp(
        r'[\u00D8-\u00DB\u00C3\u00C6\u00C7\u00D0\u00D1\u00DE]',
      ).hasMatch(value);
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

int _mojibakeMarkerCount(String value) {
  return RegExp(
    r'[\uFFFD\u00D8-\u00DB\u00C3\u00C6\u00C7\u00D0\u00D1\u00DE]',
  ).allMatches(value).length;
}

int _textQualityScore(String value) {
  if (value.isEmpty) return -9999;
  final arabic = _arabicCount(value);
  final markers = _mojibakeMarkerCount(value);
  final length = value.length;
  // Prefer human-readable Arabic text and strongly penalize mojibake markers.
  return (arabic * 5) + length - (markers * 12);
}

