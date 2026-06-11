import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../utils/parsers.dart';

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

bool _looksCorruptedText(String value) {
  if (value.isEmpty) return false;
  if (value.contains('\uFFFD')) return true;
  if (value.contains('\u00C3') ||
      value.contains('\u00E2') ||
      value.contains('\u00C5')) {
    return true;
  }
  return RegExp(
    r'[\u00C3\u00C6\u00C7\u00D0\u00D1\u00D8-\u00DB\u00DE]',
  ).hasMatch(value);
}

bool _looksQuestionMarkCorruption(String value) {
  if (value.isEmpty) return false;
  final qCount = '?'.allMatches(value).length;
  if (qCount == 0) return false;
  return qCount >= 2 && qCount * 2 >= value.length;
}

bool _looksArabicText(String value) {
  return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}

int _arabicCount(String value) {
  return RegExp(r'[\u0600-\u06FF]').allMatches(value).length;
}

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
  final bytes = _encodeMixedWindows1252Like(value);
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } catch (_) {
    return value;
  }
}

String _repairMojibakeText(String value) {
  if (!_looksCorruptedText(value)) return value;

  var current = value;
  var currentArabicScore = _arabicCount(current);

  for (var i = 0; i < 6; i++) {
    final repaired = _decodeWindows1252Utf8Pass(current);
    if (repaired == current) break;

    final repairedArabicScore = _arabicCount(repaired);
    final isBetter =
        repairedArabicScore >= currentArabicScore ||
        (_looksCorruptedText(current) && !_looksCorruptedText(repaired));
    if (!isBetter) break;

    current = repaired;
    currentArabicScore = repairedArabicScore;

    if (_looksArabicText(current) && !_looksCorruptedText(current)) {
      break;
    }
  }

  if (_looksArabicText(current) || !_looksCorruptedText(current)) {
    return current;
  }
  return value;
}

extension LocaleTextX on BuildContext {
  bool get isEnglishLocale =>
      Localizations.localeOf(this).languageCode.toLowerCase() == 'en';

  TextDirection get appTextDirection =>
      isEnglishLocale ? TextDirection.ltr : TextDirection.rtl;

  String localizedText({required String ar, required String en}) =>
      lt(ar: ar, en: en);

  String lt({required String ar, required String en}) {
    final safeAr = normalizeText(_repairMojibakeText(ar));
    final safeEn = normalizeText(_repairMojibakeText(en));
    if (isEnglishLocale) return safeEn;
    if (!isEnglishLocale &&
        (_looksCorruptedText(safeAr) || _looksQuestionMarkCorruption(safeAr)) &&
        !_looksArabicText(safeAr)) {
      return safeEn;
    }
    return safeAr;
  }
}

