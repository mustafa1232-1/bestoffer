import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'local_media_file.dart';

bool _androidPhotoPickerConfigured = false;

/// Forces the modern Android system Photo Picker (the gallery UI). Without this,
/// image_picker falls back to ACTION_GET_CONTENT, which opens the Files /
/// Documents chooser — the exact "it opens Files, not the gallery" symptom.
void _ensureAndroidPhotoPicker() {
  if (_androidPhotoPickerConfigured) return;
  final implementation = ImagePickerPlatform.instance;
  if (implementation is ImagePickerAndroid) {
    implementation.useAndroidPhotoPicker = true;
  }
  _androidPhotoPickerConfigured = true;
}

/// Opens the device **gallery / photos ("studio")** to pick a single image or
/// video — not the Files/documents browser. Used by stories and reels so the
/// user lands in their photo gallery. Returns a path-backed [LocalMediaFile]
/// (no in-memory bytes, so large videos stay light) with a resolved mimeType.
Future<LocalMediaFile?> pickGalleryMediaFromDevice() async {
  _ensureAndroidPhotoPicker();
  try {
    final picker = ImagePicker();
    final XFile? file = await picker.pickMedia();
    if (file == null) return null;
    final path = file.path;
    if (path.isEmpty) return null;

    final extension = path.contains('.')
        ? path.split('.').last.toLowerCase()
        : '';
    final resolvedMime = (file.mimeType != null && file.mimeType!.contains('/'))
        ? file.mimeType!
        : _guessMimeType(extension);

    return LocalMediaFile(
      name: file.name.isEmpty ? 'gallery_media' : file.name,
      path: path,
      bytes: null,
      mimeType: resolvedMime,
    );
  } catch (_) {
    return null;
  }
}

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

Future<List<LocalMediaFile>> pickMultiplePostMediaFromDevice({
  int maxFiles = 10,
}) async {
  try {
    _ensureAndroidPhotoPicker();
    final picker = ImagePicker();
    final files = await picker.pickMultipleMedia(
      limit: maxFiles,
      requestFullMetadata: true,
    );
    return buildLocalMediaFilesFromPickedMedia(files, maxFiles: maxFiles);
  } catch (_) {
    return const <LocalMediaFile>[];
  }
}

List<LocalMediaFile> buildLocalMediaFilesFromPickedMedia(
  Iterable<XFile> files, {
  int maxFiles = 10,
}) {
  final out = <LocalMediaFile>[];
  for (final file in files.take(maxFiles)) {
    final path = file.path.trim();
    if (path.isEmpty) continue;
    final extension = path.contains('.')
        ? path.split('.').last.toLowerCase()
        : '';
    final resolvedMime =
        (file.mimeType != null && file.mimeType!.contains('/'))
        ? file.mimeType!
        : _guessMimeType(extension);
    final resolvedName = (() {
      final rawName = file.name.trim();
      if (rawName.isNotEmpty && !rawName.contains('/') && !rawName.contains('\\')) {
        return rawName;
      }
      final baseName = path.split(RegExp(r'[\\/]+')).last.trim();
      return baseName.isNotEmpty ? baseName : 'gallery_media';
    })();
    out.add(
      LocalMediaFile(
        name: resolvedName,
        path: path,
        bytes: null,
        mimeType: resolvedMime,
      ),
    );
  }
  return out;
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
  final FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: true,
    );
  } catch (_) {
    return null;
  }

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
