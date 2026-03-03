import 'package:file_picker/file_picker.dart';

import 'local_media_file.dart';

Future<LocalMediaFile?> pickPostMediaFromDevice() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
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
    default:
      return 'application/octet-stream';
  }
}

