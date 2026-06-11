String parseString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

String? parseNullableString(Object? value) {
  final text = parseString(value);
  return text.isEmpty ? null : text;
}

int parseInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

bool parseBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}
