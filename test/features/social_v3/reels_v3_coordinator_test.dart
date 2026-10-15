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
    test(
      'runtime video failure releases the player and waits for retry',
      () async {
        final c = fakeCoordinator();
        c.setItems(List.generate(3, _videoMedia));
        await _settle();
        final first = c.controllerFor(0) as FakeVideoPlayerController;
        first.value = first.value.copyWith(errorDescription: 'offline');
        await _settle();
        expect(c.isFailed(0), isTrue);
        expect(c.isBuffering(0), isFalse);
        expect(first.disposed, isTrue);
        c.setItems(List.generate(3, _videoMedia));
        expect(c.controllerFor(0), isNull);
        c.retry(0);
        await _settle();
        expect(c.isFailed(0), isFalse);
        expect(c.controllerFor(0)!.value.isPlaying, isTrue);
        c.dispose();
      },
    );

    test('retains only {active, next} controllers', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(6, _videoMedia));
      await c.setActiveIndex(2);
      await _settle();

      expect(c.controllerFor(1), isNull);
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
      final next = c.controllerFor(2) as FakeVideoPlayerController;
      expect(active.value.isPlaying, isTrue);
      expect(c.controllerFor(0), isNull);
      expect(next.value.isPlaying, isFalse);
      c.dispose();
    });

    test('advancing disposes the now-distant controller', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(6, _videoMedia));
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

    test('refreshing the active item preserves a manual pause', () async {
      final c = fakeCoordinator();
      c.setItems(List.generate(3, _videoMedia));
      await _settle();
      c.togglePlay();
      c.setItems(List.generate(3, _videoMedia));
      await c.setActiveIndex(0);
      await _settle();
      expect(c.controllerFor(0)!.value.isPlaying, isFalse);
      expect(c.isActivePaused, isTrue);
      c.dispose();
    });

    test(
      'rapidly traversing 25 reels leaves at most two live controllers',
      () async {
        final c = fakeCoordinator();
        c.setItems(List.generate(25, _videoMedia));
        final retired = <FakeVideoPlayerController>[];
        for (var index = 0; index < 25; index++) {
          if (index > 0) {
            retired.add(
              c.controllerFor(index - 1)! as FakeVideoPlayerController,
            );
          }
          await c.setActiveIndex(index);
          await _settle();
          final live = List.generate(
            25,
            c.controllerFor,
          ).whereType<FakeVideoPlayerController>().toList();
          expect(live.length, lessThanOrEqualTo(2));
          expect(live.where((v) => v.value.isPlaying).length, 1);
          expect(retired.every((v) => v.disposed), isTrue);
        }
        final last = c.controllerFor(24)! as FakeVideoPlayerController;
        c.dispose();
        await _settle();
        expect(last.disposed, isTrue);
      },
    );

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
