import 'package:file_picker/file_picker.dart';

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

