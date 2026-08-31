import 'dart:collection';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Keeps the original [XFile] byte source alive between the native/web picker
/// and the resumable upload transport. On Web, `XFile.path` may be a blob URL
/// that cannot be opened with `dart:io File`; `XFile.openRead(start, end)` is
/// the cross-platform ranged byte source we need for TUS without loading the
/// complete video into memory.
final LinkedHashMap<String, XFile> _pickedFiles = LinkedHashMap<String, XFile>();

const int _maxRememberedPickedFiles = 12;

void registerPickedXFile(XFile file) {
  final key = file.path.trim();
  if (key.isEmpty) return;
  _pickedFiles.remove(key);
  _pickedFiles[key] = file;
  while (_pickedFiles.length > _maxRememberedPickedFiles) {
    _pickedFiles.remove(_pickedFiles.keys.first);
  }
}

Future<int?> registeredPickedFileLength(String path) async {
  final file = _pickedFiles[path.trim()];
  if (file == null) return null;
  try {
    return await file.length();
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readRegisteredPickedFileRange(
  String path,
  int start,
  int end,
) async {
  final file = _pickedFiles[path.trim()];
  if (file == null) return null;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(start, end)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
