import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'local_image_file.dart';

/// All gallery/studio image selection goes through this wrapper so every flow
/// (profile, store, product, registration, listings) behaves identically and
/// reliably.
///
/// We use [image_picker] with [ImageSource.gallery] + the Android system
/// **Photo Picker**, which is permissionless and release-safe. This fixes the
/// "gallery/studio cannot open / opens Files instead of the gallery" reports
/// (the previous wrapper used file_picker, which opens the SAF document chooser
/// and is fragile in minified release builds).
final ImagePicker _picker = ImagePicker();
bool _androidPhotoPickerConfigured = false;

/// Forces the modern Android system Photo Picker (the gallery UI). Without this,
/// image_picker falls back to ACTION_GET_CONTENT, which opens the Files /
/// Documents chooser instead of the gallery.
void _ensureAndroidPhotoPicker() {
  if (_androidPhotoPickerConfigured) return;
  final implementation = ImagePickerPlatform.instance;
  if (implementation is ImagePickerAndroid) {
    implementation.useAndroidPhotoPicker = true;
  }
  _androidPhotoPickerConfigured = true;
}

void _logMedia(String message) {
  if (kReleaseMode) return;
  debugPrint('[media-picker] $message');
}

Future<LocalImageFile?> pickImageFromDevice() async {
  _ensureAndroidPhotoPicker();
  _logMedia('pickImage(gallery) started');
  try {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2400,
      requestFullMetadata: false,
    );
    if (image == null) {
      _logMedia('pickImage canceled');
      return null;
    }
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      _logMedia('pickImage returned empty bytes');
      return null;
    }
    _logMedia('pickImage succeeded (${bytes.length} bytes)');
    return LocalImageFile(
      name: image.name.isEmpty ? 'image.jpg' : image.name,
      path: image.path,
      bytes: bytes,
    );
  } catch (e) {
    _logMedia('pickImage failed: $e');
    return null;
  }
}

Future<List<LocalImageFile>> pickMultipleImagesFromDevice({
  int maxFiles = 10,
}) async {
  _ensureAndroidPhotoPicker();
  _logMedia('pickMultiImage(gallery) started');
  try {
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 92,
      maxWidth: 2400,
      requestFullMetadata: false,
    );
    if (images.isEmpty) {
      _logMedia('pickMultiImage canceled/empty');
      return const <LocalImageFile>[];
    }
    final out = <LocalImageFile>[];
    for (final image in images.take(maxFiles)) {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) continue;
      out.add(
        LocalImageFile(
          name: image.name.isEmpty ? 'image.jpg' : image.name,
          path: image.path,
          bytes: bytes,
        ),
      );
    }
    _logMedia('pickMultiImage succeeded (${out.length} files)');
    return out;
  } catch (e) {
    _logMedia('pickMultiImage failed: $e');
    return const <LocalImageFile>[];
  }
}

Future<LocalImageFile?> captureImageFromCamera() async {
  _logMedia('captureImage(camera) started');
  try {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) return null;
    _logMedia('captureImage succeeded');
    return LocalImageFile(
      name: image.name.isEmpty ? 'camera_image.jpg' : image.name,
      path: image.path,
      bytes: bytes,
    );
  } catch (e) {
    _logMedia('captureImage failed: $e');
    return null;
  }
}
