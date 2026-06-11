import 'package:file_picker/file_picker.dart';

import 'local_media_file.dart';

Future<LocalMediaFile?> pickChatImageFromDevice() {
  return _pickSingleFile(
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
  );
}

Future<LocalMediaFile?> pickChatVideoFromDevice() {
  return _pickSingleFile(
    allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv', '3gp'],
  );
}

Future<LocalMediaFile?> pickChatFileFromDevice() {
  return _pickSingleFile(
    allowedExtensions: const [
      'pdf',
      'txt',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'zip',
      'rar',
    ],
  );
}

Future<LocalMediaFile?> pickPostMediaFromDevice() async {
  return _pickSingleFile(
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'mp4',
      'mov',
      'webm',
      'mkv',
      '3gp',
    ],
  );
}

Future<LocalMediaFile?> pickChatAttachmentFromDevice() async {
  return _pickSingleFile(
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'mp4',
      'mov',
      'webm',
      'mkv',
      '3gp',
      'pdf',
      'txt',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'zip',
      'rar',
    ],
  );
}

Future<LocalMediaFile?> pickJobApplicationAttachmentFromDevice() async {
  return _pickSingleFile(
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'],
  );
}

Future<LocalMediaFile?> _pickSingleFile({
  required List<String> allowedExtensions,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    allowMultiple: false,
    withData: true,
  );

  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if ((file.path == null || file.path!.isEmpty) &&
      (file.bytes == null || file.bytes!.isEmpty)) {
    return null;
  }

  final extension = file.extension?.toLowerCase() ?? '';
  final mimeType = _guessMimeType(extension);

  return LocalMediaFile(
    name: file.name,
    path: file.path,
    bytes: file.bytes,
    mimeType: mimeType,
  );
}

String _guessMimeType(String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'mkv':
      return 'video/x-matroska';
    case '3gp':
      return 'video/3gpp';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'zip':
      return 'application/zip';
    case 'rar':
      return 'application/vnd.rar';
    default:
      return 'application/octet-stream';
  }
}
