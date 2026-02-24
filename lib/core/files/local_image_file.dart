import 'dart:typed_data';

import 'package:dio/dio.dart';

class LocalImageFile {
  final String name;
  final String? path;
  final Uint8List? bytes;

  const LocalImageFile({
    required this.name,
    required this.path,
    required this.bytes,
  });

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;

  Future<MultipartFile> toMultipartFile() async {
    if (hasBytes) {
      return MultipartFile.fromBytes(bytes!, filename: name);
    }
    if (path != null && path!.isNotEmpty) {
      return MultipartFile.fromFile(path!, filename: name);
    }
    throw StateError('Image file has no readable bytes or path');
  }
}

