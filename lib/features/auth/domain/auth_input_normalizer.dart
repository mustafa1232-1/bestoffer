String normalizeAuthDigits(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660));
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0));
      continue;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}

String normalizeAuthPin(String value) => normalizeAuthDigits(value).trim();

String normalizeIraqiPhoneForAuth(String value) {
  final normalizedDigits = normalizeAuthDigits(value).trim();
  if (normalizedDigits.isEmpty) return '';

  final hasInternationalPlus = normalizedDigits.startsWith('+');
  final compact = normalizedDigits.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  final digits = compact.replaceAll(RegExp(r'[^0-9]'), '');

  if (digits.startsWith('9647') && digits.length == 13) {
    return '0${digits.substring(3)}';
  }
  if (digits.startsWith('7') && digits.length == 10) {
    return '0$digits';
  }
  if (digits.startsWith('07') && digits.length == 11) {
    return digits;
  }

  if (hasInternationalPlus) return compact;
  return digits.isEmpty ? compact : digits;
}

bool isPlausibleIraqiAuthPhone(String value) {
  return RegExp(r'^07\d{9}$').hasMatch(normalizeIraqiPhoneForAuth(value));
}
