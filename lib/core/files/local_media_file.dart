import 'dart:typed_data';

import 'package:dio/dio.dart';

class LocalMediaFile {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final String? mimeType;

  const LocalMediaFile({
    required this.name,
    required this.path,
    required this.bytes,
    this.mimeType,
  });

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;

  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');

  Future<MultipartFile> toMultipartFile() async {
    if (hasBytes) {
      return MultipartFile.fromBytes(
        bytes!,
        filename: name,
        contentType: _resolveMediaType(mimeType),
      );
    }
    if (path != null && path!.isNotEmpty) {
      return MultipartFile.fromFile(
        path!,
        filename: name,
        contentType: _resolveMediaType(mimeType),
      );
    }
    throw StateError('Media file has no readable bytes or path');
  }
}

DioMediaType? _resolveMediaType(String? mimeType) {
  final raw = (mimeType ?? '').trim().toLowerCase();
  if (!raw.contains('/')) return null;
  final parts = raw.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
  return DioMediaType(parts[0], parts[1]);
}
