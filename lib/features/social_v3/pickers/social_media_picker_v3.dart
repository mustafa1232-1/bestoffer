import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Media type of a picked social asset.
enum PickedMediaType { image, video }

/// Typed result of a native gallery pick (§2). Never carries the file bytes for
/// large videos — only the path + metadata.
@immutable
class PickedSocialMedia {
  const PickedSocialMedia({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.type,
    this.width,
    this.height,
    this.durationMs,
  });

  final String path;
  final String name;
  final String? mimeType;
  final int? sizeBytes;
  final PickedMediaType type;
  final int? width;
  final int? height;
  final int? durationMs;

  bool get isVideo => type == PickedMediaType.video;
}

/// Raised when a picker fails (never swallowed silently — §2). Cancellation is
/// represented by a `null` return, not an exception.
class SocialPickerException implements Exception {
  const SocialPickerException(this.stage, this.cause);
  final String stage;
  final Object cause;
  @override
  String toString() => 'SocialPickerException($stage): $cause';
}

/// The authoritative native picker surface for Social V3.
///
/// Android uses the system Photo Picker (the app pins `image_picker_android` to
/// force it instead of the legacy documents chooser); iOS uses PHPicker. Reel
/// picks are **video-only**; story/post picks allow the appropriate media.
/// `FilePicker` is intentionally NOT used here — it is reserved for real
/// documents/attachments elsewhere.
class SocialMediaPickerV3 {
  SocialMediaPickerV3({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Reel: video only (§2). Returns null if the user cancels.
  Future<PickedSocialMedia?> pickReelVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return null;
      return await _toResult(file, PickedMediaType.video);
    } catch (error) {
      throw SocialPickerException('pickReelVideo', error);
    }
  }

  /// Story: a single image or video.
  Future<PickedSocialMedia?> pickStoryImageOrVideo() async {
    try {
      final file = await _picker.pickMedia();
      if (file == null) return null;
      return await _toResult(file, _inferType(file));
    } catch (error) {
      throw SocialPickerException('pickStoryImageOrVideo', error);
    }
  }

  /// Story: image only.
  Future<PickedSocialMedia?> pickStoryImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return null;
      return await _toResult(file, PickedMediaType.image);
    } catch (error) {
      throw SocialPickerException('pickStoryImage', error);
    }
  }

  /// Story: video only.
  Future<PickedSocialMedia?> pickStoryVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return null;
      return await _toResult(file, PickedMediaType.video);
    } catch (error) {
      throw SocialPickerException('pickStoryVideo', error);
    }
  }

  /// Post: a single image or video.
  Future<PickedSocialMedia?> pickPostImageOrVideo() async {
    try {
      final file = await _picker.pickMedia();
      if (file == null) return null;
      return await _toResult(file, _inferType(file));
    } catch (error) {
      throw SocialPickerException('pickPostImageOrVideo', error);
    }
  }

  /// Post: multiple images/videos.
  Future<List<PickedSocialMedia>> pickMultiplePostMedia() async {
    try {
      final files = await _picker.pickMultipleMedia();
      final out = <PickedSocialMedia>[];
      for (final file in files) {
        out.add(await _toResult(file, _inferType(file)));
      }
      return out;
    } catch (error) {
      throw SocialPickerException('pickMultiplePostMedia', error);
    }
  }

  static PickedMediaType _inferType(XFile file) =>
      inferMediaTypeFromNameOrMime(name: file.name, mimeType: file.mimeType);

  Future<PickedSocialMedia> _toResult(XFile file, PickedMediaType type) async {
    final normalized = await _materializePickedFile(file);
    // NOTE: never read the whole file into memory (no `readAsBytes` for video).
    int? size;
    try {
      size = await normalized.length();
    } catch (_) {
      size = null;
    }
    return PickedSocialMedia(
      path: normalized.path,
      name: normalized.name.isNotEmpty ? normalized.name : file.name,
      mimeType: normalized.mimeType ?? file.mimeType ?? _mimeFromName(file.name, type),
      sizeBytes: size,
      type: type,
    );
  }

  Future<XFile> _materializePickedFile(XFile file) async {
    final sourcePath = file.path.trim();
    if (sourcePath.isEmpty) return file;

    try {
      final safeName = file.name.trim().isNotEmpty
          ? file.name.trim()
          : p.basename(sourcePath).trim();
      final tempRoot = Directory(
        p.join(Directory.systemTemp.path, 'bestoffer_social_picker'),
      );
      await tempRoot.create(recursive: true);
      final destination = File(
        p.join(
          tempRoot.path,
          '${DateTime.now().microsecondsSinceEpoch}_$safeName',
        ),
      );
      final sink = destination.openWrite();
      try {
        await sink.addStream(file.openRead());
      } finally {
        await sink.close();
      }
      return XFile(
        destination.path,
        name: safeName.isNotEmpty ? safeName : destination.path,
        mimeType: file.mimeType,
      );
    } catch (_) {
      return file;
    }
  }
}

/// Pure helper (unit-testable without platform channels): decides image vs
/// video from a name/MIME.
PickedMediaType inferMediaTypeFromNameOrMime({
  required String name,
  String? mimeType,
}) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.startsWith('video/')) return PickedMediaType.video;
  if (mime.startsWith('image/')) return PickedMediaType.image;
  final lower = name.toLowerCase();
  const videoExt = ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.3gp', '.avi'];
  if (videoExt.any(lower.endsWith)) return PickedMediaType.video;
  return PickedMediaType.image;
}

String _mimeFromName(String name, PickedMediaType type) {
  final lower = name.toLowerCase();
  if (type == PickedMediaType.video) {
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'video/mp4';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
