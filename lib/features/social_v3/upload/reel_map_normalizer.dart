class ReelInvalidResponseException implements Exception {
  const ReelInvalidResponseException(this.code);

  final String code;

  @override
  String toString() => 'ReelInvalidResponseException($code)';
}

Map<String, dynamic> normalizeReelMap(dynamic raw, String code) {
  if (raw is! Map) {
    throw ReelInvalidResponseException(code);
  }
  return raw.map(
    (key, value) => MapEntry<String, dynamic>(
      key.toString(),
      normalizeReelJsonValue(value),
    ),
  );
}

Map<String, dynamic>? normalizeOptionalMap(dynamic raw, {String? code}) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw ReelInvalidResponseException(code ?? 'INVALID_REEL_STYLE');
  }
  return raw.map(
    (key, value) => MapEntry<String, dynamic>(
      key.toString(),
      normalizeReelJsonValue(value),
    ),
  );
}

dynamic normalizeReelJsonValue(dynamic raw) {
  if (raw is Map) {
    return raw.map(
      (key, value) => MapEntry<String, dynamic>(
        key.toString(),
        normalizeReelJsonValue(value),
      ),
    );
  }
  if (raw is Iterable) {
    return raw.map(normalizeReelJsonValue).toList(growable: false);
  }
  return raw;
}
