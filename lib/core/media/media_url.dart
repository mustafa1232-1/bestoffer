import '../constants/api.dart';

/// Normalizes a raw media URL coming from the backend / DB into a loadable,
/// transport-safe absolute URL.
///
/// Why this exists: posts arrive for everyone, but media fails to load for
/// *some* users. The usual causes are transport/format issues that only bite on
/// stricter devices or OS versions:
///   - `http://` URLs blocked by Android cleartext policy / iOS ATS (works on
///     lenient devices, fails on strict ones — the classic "some users" symptom)
///   - relative or scheme-less paths stored in the DB (`/uploads/x.jpg`)
///   - spaces / Arabic characters that were never percent-encoded
///
/// Returns `null` for empty input so callers can render a placeholder.
String? resolveMediaUrl(String? raw, {String? baseUrl}) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;

  // Already self-contained.
  if (value.startsWith('data:')) return value;
  if (value.startsWith('blob:')) return value;

  final base = (baseUrl ?? Api.baseUrl).trim();
  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;

  // Protocol-relative `//cdn/...` -> https.
  if (value.startsWith('//')) {
    return _encodeIfNeeded('https:$value');
  }

  // Absolute path relative to the API host: `/uploads/foo.jpg`.
  if (value.startsWith('/')) {
    return _encodeIfNeeded('$normalizedBase$value');
  }

  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(value);
  if (!hasScheme) {
    // Scheme-less relative path: `uploads/foo.jpg`.
    return _encodeIfNeeded('$normalizedBase/$value');
  }

  // Upgrade http -> https for non-local hosts so strict Android/iOS transport
  // policies do not silently drop the request. Local/emulator hosts are left
  // as cleartext (dev convenience; release builds never use them).
  if (value.toLowerCase().startsWith('http://')) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty && !_isLocalHost(uri.host)) {
      return _encodeIfNeeded(
        'https://${value.substring('http://'.length)}',
      );
    }
  }

  return _encodeIfNeeded(value);
}

bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '10.0.2.2' || // Android emulator
      h == '10.0.3.2' || // Genymotion
      h.startsWith('192.168.') ||
      h.startsWith('10.') ||
      h.startsWith('172.');
}

/// Percent-encodes spaces / non-ASCII characters in a URL that was stored
/// unencoded, without double-encoding a URL that is already encoded.
String _encodeIfNeeded(String url) {
  final hasUnsafe = url.contains(' ') || url.runes.any((rune) => rune > 0x7F);
  if (!hasUnsafe) return url;
  final alreadyEncoded = RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(url);
  if (alreadyEncoded) return url;
  return Uri.encodeFull(url);
}
