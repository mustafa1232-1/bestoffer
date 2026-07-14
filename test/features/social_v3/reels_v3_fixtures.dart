import 'package:flutter/widgets.dart';
import 'package:maslaki/features/social_v3/domain/reel_view_data.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';
import 'package:maslaki/features/social_v3/reels/reel_playback_coordinator.dart';
import 'package:video_player/video_player.dart';

/// A deterministic reel with a poster-only (no live video) presentation, so
/// widget/golden tests render the poster state with no network or platform
/// channel involved.
ReelV3ViewData fakeReel({
  int id = 1,
  String name = 'creationwithjacki',
  String handle = '@creationwithjacki',
  String caption =
      'Non-followers aren\'t seeing your reels because you forgot to do this',
  int likes = 4470,
  int comments = 128,
  int saves = 64,
  bool verified = true,
  String? localBadge = 'Block 12',
  bool vertical = true,
  bool withPoster = false,
}) {
  return ReelV3ViewData(
    postId: id,
    authorId: id,
    authorName: name,
    authorHandle: handle,
    authorAvatarUrl: null,
    isAuthorVerified: verified,
    caption: caption,
    media: SocialMediaPresentation(
      mediaAssetId: id,
      provider: 'cloudflare_stream',
      mediaKind: SocialMediaKind.reel,
      playbackType: SocialPlaybackType.none,
      videoPlaybackUrl: null,
      posterImageUrl: withPoster ? 'https://example.test/p.jpg' : null,
      width: vertical ? 1080 : 1920,
      height: vertical ? 1920 : 1080,
      durationMs: 15000,
      processingStatus: SocialProcessingStatus.ready,
    ),
    likesCount: likes,
    commentsCount: comments,
    savesCount: saves,
    viewsCount: 4470079,
    isLiked: false,
    isSaved: false,
    audioLabel: 'Original audio',
    localContextBadge: localBadge,
  );
}

List<ReelV3ViewData> fakeReels(int n) =>
    List.generate(n, (i) => fakeReel(id: i + 1, name: 'user_${i + 1}'));

/// A [VideoPlayerController] that never touches the platform channel — for
/// coordinator tests. It records play/pause/dispose calls.
class FakeVideoPlayerController extends VideoPlayerController {
  FakeVideoPlayerController(this.url)
    : super.networkUrl(Uri.parse('https://fake.test/placeholder.mp4'));

  final String url;
  bool initialized = false;
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    initialized = true;
    value = value.copyWith(
      isInitialized: true,
      size: const Size(1080, 1920),
      duration: const Duration(seconds: 15),
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

ReelPlaybackCoordinator fakeCoordinator() =>
    ReelPlaybackCoordinator(controllerFactory: FakeVideoPlayerController.new);
