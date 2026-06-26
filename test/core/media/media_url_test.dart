import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/media/media_url.dart';

void main() {
  const base = 'https://cdn.example.com';

  test('returns null for empty/whitespace input', () {
    expect(resolveMediaUrl(null), isNull);
    expect(resolveMediaUrl(''), isNull);
    expect(resolveMediaUrl('   '), isNull);
  });

  test('keeps an already-valid https URL unchanged', () {
    const url = 'https://cdn.example.com/uploads/photo_123.jpg';
    expect(resolveMediaUrl(url, baseUrl: base), url);
  });

  test('upgrades http -> https for remote hosts (Android cleartext / iOS ATS)', () {
    expect(
      resolveMediaUrl('http://cdn.example.com/a.jpg', baseUrl: base),
      'https://cdn.example.com/a.jpg',
    );
  });

  test('leaves http for local/emulator hosts (dev convenience)', () {
    expect(
      resolveMediaUrl('http://10.0.2.2:3000/uploads/a.jpg', baseUrl: base),
      'http://10.0.2.2:3000/uploads/a.jpg',
    );
    expect(
      resolveMediaUrl('http://localhost:3000/uploads/a.jpg', baseUrl: base),
      'http://localhost:3000/uploads/a.jpg',
    );
  });

  test('prefixes absolute paths with the base URL', () {
    expect(
      resolveMediaUrl('/uploads/a.jpg', baseUrl: base),
      'https://cdn.example.com/uploads/a.jpg',
    );
  });

  test('prefixes scheme-less relative paths with the base URL', () {
    expect(
      resolveMediaUrl('uploads/a.jpg', baseUrl: base),
      'https://cdn.example.com/uploads/a.jpg',
    );
  });

  test('expands protocol-relative URLs to https', () {
    expect(
      resolveMediaUrl('//cdn.example.com/a.jpg', baseUrl: base),
      'https://cdn.example.com/a.jpg',
    );
  });

  test('percent-encodes spaces and Arabic characters when unencoded', () {
    final out = resolveMediaUrl('/uploads/صورة جديدة.jpg', baseUrl: base)!;
    expect(out.contains(' '), isFalse);
    expect(out.startsWith('https://cdn.example.com/uploads/'), isTrue);
    expect(out.contains('%'), isTrue);
  });

  test('does not double-encode an already-encoded URL', () {
    const url = 'https://cdn.example.com/uploads/%D8%B5%D9%88%D8%B1%D8%A9.jpg';
    expect(resolveMediaUrl(url, baseUrl: base), url);
  });

  test('passes through data URIs untouched', () {
    const dataUri = 'data:image/png;base64,iVBORw0KGgo=';
    expect(resolveMediaUrl(dataUri, baseUrl: base), dataUri);
  });
}
