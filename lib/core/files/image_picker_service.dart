import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'local_image_file.dart';

Future<LocalImageFile?> pickImageFromDevice() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.first;
  if ((file.path == null || file.path!.isEmpty) &&
      (file.bytes == null || file.bytes!.isEmpty)) {
    return null;
  }

  return LocalImageFile(
    name: file.name,
    path: file.path,
    bytes: file.bytes,
  );
}

Future<List<LocalImageFile>> pickMultipleImagesFromDevice({
  int maxFiles = 10,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,
  );

  if (result == null || result.files.isEmpty) {
    return const <LocalImageFile>[];
  }

  return result.files
      .take(maxFiles)
      .where(
        (file) =>
            ((file.path ?? '').isNotEmpty) ||
            (file.bytes != null && file.bytes!.isNotEmpty),
      )
      .map(
        (file) => LocalImageFile(
          name: file.name,
          path: file.path,
          bytes: file.bytes,
        ),
      )
      .toList(growable: false);
}

Future<LocalImageFile?> captureImageFromCamera() async {
  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 92,
    maxWidth: 2400,
  );
  if (image == null) return null;

  final bytes = await image.readAsBytes();
  if (bytes.isEmpty) return null;

  return LocalImageFile(
    name: image.name.isEmpty ? 'camera_image.jpg' : image.name,
    path: image.path,
    bytes: bytes,
  );
}
