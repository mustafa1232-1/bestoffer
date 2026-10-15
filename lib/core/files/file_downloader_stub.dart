import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> downloadBytesFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final file = XFile.fromData(bytes, mimeType: mimeType);
  await SharePlus.instance.share(
    ShareParams(files: [file], fileNameOverrides: [filename]),
  );
}
