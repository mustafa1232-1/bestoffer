import 'dart:io';

import 'package:image/image.dart' as img;

import 'creator_filter_registry.dart';
import 'creator_temp_media_service.dart';

class FilterPipelineService {
  final CreatorTempMediaService tempMediaService;

  const FilterPipelineService(this.tempMediaService);

  Future<File> exportPhoto({
    required File sourceImage,
    required String? filterId,
  }) async {
    final preset = resolveCreatorFilterPreset(filterId);
    if (preset.id == creatorNoFilter.id) {
      return tempMediaService.cleanupAndCopy(sourceImage, prefix: 'story_photo');
    }
    final bytes = await sourceImage.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unable to decode captured image.');
    }
    final rendered = img.copyResize(decoded, width: decoded.width);
    _applyFilter(rendered, preset.id);
    final outputPath = await tempMediaService.newFilePath(
      prefix: 'story_photo_filtered',
      extension: 'jpg',
    );
    final encoded = img.encodeJpg(rendered, quality: 92);
    return File(outputPath)..writeAsBytesSync(encoded, flush: true);
  }

  void applyPreviewFilter(img.Image image, String? filterId) {
    final preset = resolveCreatorFilterPreset(filterId);
    _applyFilter(image, preset.id);
  }

  void _applyFilter(img.Image image, String filterId) {
    switch (filterId) {
      case 'basmaya_glow':
        img.adjustColor(image, brightness: 1.03, contrast: 1.05, saturation: 1.08);
        img.vignette(image, start: 0.12, end: 0.92, amount: 0.16);
        break;
      case 'desert_honey':
        img.adjustColor(image, brightness: 1.02, contrast: 1.04, saturation: 1.10, hue: -4);
        img.sepia(image, amount: 0.24);
        break;
      case 'indigo_night':
        img.adjustColor(image, brightness: 0.98, contrast: 1.08, saturation: 1.06, hue: 7);
        img.vignette(image, start: 0.08, end: 0.88, amount: 0.24);
        break;
      case 'soft_sand':
        img.adjustColor(image, brightness: 1.01, contrast: 1.01, saturation: 0.95, hue: -2);
        break;
      case 'date_palm':
        img.adjustColor(image, brightness: 1.00, contrast: 1.03, saturation: 1.04, hue: 3);
        break;
      case 'neon_souq':
        img.adjustColor(image, brightness: 1.01, contrast: 1.08, saturation: 1.18, hue: 9);
        img.vignette(image, start: 0.16, end: 0.92, amount: 0.12);
        break;
      case 'morning_dust':
        img.adjustColor(image, brightness: 1.04, contrast: 0.98, saturation: 0.92, hue: -3);
        break;
      case 'pearl_skin':
        img.adjustColor(image, brightness: 1.05, contrast: 1.01, saturation: 0.98);
        break;
      case 'warm_street':
        img.adjustColor(image, brightness: 1.02, contrast: 1.05, saturation: 1.04, hue: -6);
        break;
      case 'royal_indigo':
        img.adjustColor(image, brightness: 1.00, contrast: 1.07, saturation: 1.10, hue: 11);
        img.vignette(image, start: 0.10, end: 0.90, amount: 0.18);
        break;
      case 'none':
      default:
        break;
    }
  }
}
