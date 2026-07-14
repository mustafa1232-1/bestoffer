import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';

void main() {
  group('inferMediaTypeFromNameOrMime', () {
    test('MIME wins over extension', () {
      expect(
        inferMediaTypeFromNameOrMime(name: 'x.jpg', mimeType: 'video/mp4'),
        PickedMediaType.video,
      );
      expect(
        inferMediaTypeFromNameOrMime(name: 'x.mp4', mimeType: 'image/png'),
        PickedMediaType.image,
      );
    });

    test('falls back to extension', () {
      expect(
        inferMediaTypeFromNameOrMime(name: 'clip.MOV'),
        PickedMediaType.video,
      );
      expect(
        inferMediaTypeFromNameOrMime(name: 'photo.HEIC'),
        PickedMediaType.image,
      );
      expect(
        inferMediaTypeFromNameOrMime(name: 'reel.webm', mimeType: ''),
        PickedMediaType.video,
      );
    });
  });

  test('PickedSocialMedia.isVideo reflects the type', () {
    const media = PickedSocialMedia(
      path: '/tmp/a.mp4',
      name: 'a.mp4',
      mimeType: 'video/mp4',
      sizeBytes: 1024,
      type: PickedMediaType.video,
    );
    expect(media.isVideo, isTrue);
  });
}
