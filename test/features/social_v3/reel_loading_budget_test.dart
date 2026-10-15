import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/reels/reel_playback_coordinator.dart';
import 'reels_v3_fixtures.dart';

class _DelayedVideo extends FakeVideoPlayerController {
  _DelayedVideo(super.url);
  final gate = Completer<void>();
  @override
  Future<void> initialize() async {
    await gate.future;
    await super.initialize();
  }
}

void main() {
  test(
    'current reel initializes before next and rapid swipes discard stale players',
    () async {
      final created = <_DelayedVideo>[];
      final coordinator = ReelPlaybackCoordinator(
        controllerFactory: (url) {
          final player = _DelayedVideo(url);
          created.add(player);
          return player;
        },
      );
      coordinator.setItems(
        List.generate(4, (i) => fakeReel(id: i + 1, withVideo: true).media),
      );
      expect(created.length, 1);
      created[0].gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(created.length, 2);
      expect(created[0].playCalls, 1);
      await coordinator.setActiveIndex(2);
      expect(created[0].disposed, isTrue);
      expect(created[1].disposed, isTrue);
      expect(created.length, 3);
      created[1].gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(created[1].playCalls, 0);
      created[2].gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(created.length, 4);
      coordinator.dispose();
      created[3].gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(created.every((player) => player.disposed), isTrue);
    },
  );
}
