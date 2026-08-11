String? resolveSocialMediaUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  if (value.startsWith('data:') || value.startsWith('blob:')) return value;

  if (value.startsWith('//')) {
    return _encodeIfNeeded('https:$value');
  }

  if (value.toLowerCase().startsWith('http://')) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty && !_isLocalHost(uri.host)) {
      return _encodeIfNeeded('https://${value.substring('http://'.length)}');
    }
  }

  return _encodeIfNeeded(value);
}

bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '10.0.2.2' ||
      h == '10.0.3.2' ||
      h.startsWith('192.168.') ||
      h.startsWith('10.') ||
      h.startsWith('172.');
}

String _encodeIfNeeded(String url) {
  final hasUnsafe = url.contains(' ') || url.runes.any((rune) => rune > 0x7F);
  if (!hasUnsafe) return url;
  final alreadyEncoded = RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(url);
  if (alreadyEncoded) return url;
  return Uri.encodeFull(url);
}
