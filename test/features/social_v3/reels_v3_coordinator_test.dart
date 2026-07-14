import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';

import 'reels_v3_fixtures.dart';

SocialMediaPresentation _videoMedia(int i) => SocialMediaPresentation(
  mediaAssetId: i,
  provider: 'cloudflare_stream',
  mediaKind: SocialMediaKind.reel,
  playbackType: SocialPlaybackType.hls,
  videoPlaybackUrl: 'https://videodelivery.net/uid$i/manifest/video.m3u8',
  posterImageUrl: 'https://x/poster$i.jpg',
  width: 1080,
  height: 1920,
  durationMs: 15000,
  processingStatus: SocialProcessingStatus.ready,
);

/// Flush the microtasks that back the fake controller's `initialize().then(...)`.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('ReelPlaybackCoordinator', () {
    test('retains only {prev, active, next} controllers', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(6, _videoMedia));
      await c.setActiveIndex(2);
      await _settle();

      expect(c.controllerFor(1), isNotNull);
      expect(c.controllerFor(2), isNotNull);
      expect(c.controllerFor(3), isNotNull);
      expect(c.controllerFor(0), isNull);
      expect(c.controllerFor(4), isNull);
      c.dispose();
    });

    test('only the active controller plays', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(4, _videoMedia));
      await c.setActiveIndex(1);
      await _settle();

      final active = c.controllerFor(1) as FakeVideoPlayerController;
      final prev = c.controllerFor(0) as FakeVideoPlayerController;
      final next = c.controllerFor(2) as FakeVideoPlayerController;
      expect(active.value.isPlaying, isTrue);
      expect(prev.value.isPlaying, isFalse);
      expect(next.value.isPlaying, isFalse);
      c.dispose();
    });

    test('advancing disposes the now-distant controller', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(6, _videoMedia));
      await c.setActiveIndex(1);
      await _settle();
      final zero = c.controllerFor(0) as FakeVideoPlayerController;

      await c.setActiveIndex(3);
      await _settle();
      expect(zero.disposed, isTrue);
      expect(c.controllerFor(0), isNull);
      expect(c.controllerFor(4), isNotNull);
      c.dispose();
    });

    test('mute preference is preserved across page changes', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(4, _videoMedia));
      await c.setActiveIndex(0);
      await _settle();
      c.setMuted(true);
      expect(c.isMuted, isTrue);

      await c.setActiveIndex(1);
      await _settle();
      expect(c.isMuted, isTrue, reason: 'mute must survive navigation');
      c.dispose();
    });

    test(
      'route hidden and app inactive both pause the active controller',
      () async {
        final c = fakeCoordinator();
        c.setItems(List.generate(3, _videoMedia));
        await c.setActiveIndex(0);
        await _settle();
        final active = c.controllerFor(0) as FakeVideoPlayerController;
        expect(active.value.isPlaying, isTrue);

        c.setRouteVisible(false);
        expect(active.value.isPlaying, isFalse);

        c.setRouteVisible(true);
        expect(active.value.isPlaying, isTrue);

        c.setAppActive(false);
        expect(active.value.isPlaying, isFalse);
        c.dispose();
      },
    );

    test('togglePlay flips the active play state', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(3, _videoMedia));
      await c.setActiveIndex(0);
      await _settle();
      final active = c.controllerFor(0) as FakeVideoPlayerController;
      expect(active.value.isPlaying, isTrue);
      c.togglePlay();
      expect(active.value.isPlaying, isFalse);
      c.togglePlay();
      expect(active.value.isPlaying, isTrue);
      c.dispose();
    });

    test(
      're-asserting the same active index does not recreate the controller',
      () async {
        final c = fakeCoordinator();
        c.setItems(List.generate(3, _videoMedia));
        await c.setActiveIndex(1);
        await _settle();
        final first = c.controllerFor(1);
        await c.setActiveIndex(1);
        await _settle();
        expect(
          identical(c.controllerFor(1), first),
          isTrue,
          reason: 'a like/comment rebuild must not recreate the video',
        );
        c.dispose();
      },
    );
  });
}
