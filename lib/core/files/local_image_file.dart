import 'dart:typed_data';

import 'package:dio/dio.dart';

const int kMaxUploadImageBytes = 8 * 1024 * 1024;
const Set<String> kSupportedUploadImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
};

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

  int? get sizeBytes => bytes?.length;

  String get extension {
    final normalized = name.trim().toLowerCase();
    final index = normalized.lastIndexOf('.');
    if (index < 0 || index == normalized.length - 1) return '';
    return normalized.substring(index + 1);
  }

  bool get hasSupportedExtension =>
      kSupportedUploadImageExtensions.contains(extension);

  bool get isWithinUploadLimit =>
      sizeBytes == null || sizeBytes! <= kMaxUploadImageBytes;

  String? get uploadValidationError {
    if (!hasSupportedExtension) {
      return 'UNSUPPORTED_IMAGE_FORMAT';
    }
    if (!isWithinUploadLimit) {
      return 'IMAGE_TOO_LARGE';
    }
    return null;
  }

  Future<MultipartFile> toMultipartFile() async {
    final validationError = uploadValidationError;
    if (validationError != null) {
      throw StateError(validationError);
    }
    if (hasBytes) {
      return MultipartFile.fromBytes(bytes!, filename: name);
    }
    if (path != null && path!.isNotEmpty) {
      return MultipartFile.fromFile(path!, filename: name);
    }
    throw StateError('Image file has no readable bytes or path');
  }
}
