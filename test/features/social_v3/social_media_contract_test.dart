import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';
import 'package:maslaki/features/social_v3/media/social_safe_image.dart';
import 'package:social_core/social_models.dart';

SocialMediaAsset _asset({
  String? playbackUrl,
  String? thumbnailUrl,
  String? posterUrl,
  String? normalizedUrl,
  String? streamUid,
  String? provider,
  String? processingStatus,
  int? durationMs,
}) {
  return SocialMediaAsset(
    id: 1,
    provider: provider,
    streamUid: streamUid,
    normalizedUrl: normalizedUrl,
    posterUrl: posterUrl,
    playbackUrl: playbackUrl,
    thumbnailUrl: thumbnailUrl,
    durationMs: durationMs,
    processingStatus: processingStatus,
  );
}

void main() {
  group('isStreamingManifestUrl', () {
    test('detects HLS m3u8 with and without query', () {
      expect(isStreamingManifestUrl('https://x/abc/manifest/video.m3u8'), isTrue);
      expect(isStreamingManifestUrl('https://x/v.m3u8?token=1'), isTrue);
      expect(isStreamingManifestUrl('https://x/v?format=hls'), isTrue);
    });

    test('does not flag ordinary images', () {
      expect(isStreamingManifestUrl('https://x/thumb.jpg'), isFalse);
      expect(isStreamingManifestUrl('https://x/poster.png?w=200'), isFalse);
      expect(isStreamingManifestUrl(null), isFalse);
    });
  });

  group('poster resolution never yields a playback URL', () {
    test('reel with only a playback HLS url has NO poster (falls back)', () {
      final p = SocialMediaPresentation.fromAsset(
        _asset(playbackUrl: 'https://videodelivery.net/uid/manifest/video.m3u8'),
        kind: SocialMediaKind.reel,
      );
      expect(p.posterImageUrl, isNull,
          reason: 'a manifest must never become a poster');
      expect(p.videoPlaybackUrl, isNotNull);
      expect(p.playbackType, SocialPlaybackType.hls);
    });

    test('prefers thumbnail, then poster, then provider thumbnail', () {
      expect(
        SocialMediaPresentation.fromAsset(
          _asset(thumbnailUrl: 'https://x/t.jpg', posterUrl: 'https://x/p.jpg'),
          kind: SocialMediaKind.reel,
        ).posterImageUrl,
        'https://x/t.jpg',
      );
      expect(
        SocialMediaPresentation.fromAsset(
          _asset(posterUrl: 'https://x/p.jpg'),
          kind: SocialMediaKind.reel,
        ).posterImageUrl,
        'https://x/p.jpg',
      );
      expect(
        SocialMediaPresentation.fromAsset(
          _asset(streamUid: 'abc123', provider: 'cloudflare_stream'),
          kind: SocialMediaKind.reel,
        ).posterImageUrl,
        'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
      );
    });

    test('a poster field mislabeled as a video is rejected', () {
      final p = SocialMediaPresentation.fromAsset(
        _asset(thumbnailUrl: 'https://x/bad.mp4'),
        kind: SocialMediaKind.reel,
      );
      expect(p.posterImageUrl, isNull);
    });
  });

  group('playback resolution', () {
    test('missing playback url yields none, not a fake ready state', () {
      final p = SocialMediaPresentation.fromAsset(
        _asset(thumbnailUrl: 'https://x/t.jpg'),
        kind: SocialMediaKind.reel,
      );
      expect(p.hasVideo, isFalse);
      expect(p.playbackType, SocialPlaybackType.none);
      // A missing poster must not block playback and vice-versa:
      expect(p.hasPoster, isTrue);
    });

    test('legacy mp4 normalizedUrl is progressive, not hls', () {
      final p = SocialMediaPresentation.fromAsset(
        _asset(normalizedUrl: 'https://x/legacy.mp4'),
        kind: SocialMediaKind.video,
      );
      expect(p.videoPlaybackUrl, 'https://x/legacy.mp4');
      expect(p.playbackType, SocialPlaybackType.progressiveMp4);
    });
  });

  group('processing status semantics', () {
    test('maps common values', () {
      expect(SocialProcessingStatusX.parse('processing'),
          SocialProcessingStatus.processing);
      expect(SocialProcessingStatusX.parse('READY').allowsPlayback, isTrue);
      expect(SocialProcessingStatusX.parse('draft').isCreatorOnly, isTrue);
      expect(SocialProcessingStatusX.parse('deleted').isPublicEligible, isFalse);
      // Legacy empty status stays playable.
      expect(SocialProcessingStatusX.parse('').allowsPlayback, isTrue);
    });
  });

  group('SocialSafeImage contract enforcement', () {
    testWidgets('throws in debug when given an HLS manifest', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SocialSafeImage(
            imageUrl: 'https://videodelivery.net/uid/manifest/video.m3u8',
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('throws in debug when given an MP4', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SocialSafeImage(imageUrl: 'https://x/clip.mp4'),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('renders placeholder for null url without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SocialSafeImage(imageUrl: null)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('accepts an ordinary image url', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SocialSafeImage(imageUrl: 'https://x/poster.jpg'),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
