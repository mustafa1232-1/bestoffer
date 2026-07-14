import 'package:flutter/foundation.dart';
import 'package:social_core/social_models.dart';

/// Social V3 media contract (§2).
///
/// The single source of truth for how a piece of social media is *presented*.
/// It exists to make one class of bug structurally impossible: feeding a video
/// playback URL (an HLS `.m3u8` manifest or an MP4) into an image widget, which
/// is what produced the broken circular poster in the failure baseline.
///
/// Hard rules enforced here:
///  1. [posterImageUrl] is only ever an image URL — never a manifest/MP4.
///  2. [videoPlaybackUrl] is only ever consumed by a video player.
///  3. A missing poster never blocks playback, and a missing playback URL never
///     fakes a successful video state.

/// What kind of media this is, independent of transport.
enum SocialMediaKind { reel, video, image, text, unknown }

/// How the video (if any) should be played.
enum SocialPlaybackType {
  /// Cloudflare Stream / any `.m3u8` HLS manifest — streamed, never cached as a
  /// standalone file.
  hls,

  /// A progressive MP4 (legacy R2). May use the bounded video cache.
  progressiveMp4,

  /// No playable video (image/text content, or nothing ready yet).
  none,
}

/// Lifecycle of the underlying media asset. Controls what the UI is allowed to
/// show (§2.9).
enum SocialProcessingStatus {
  draft,
  uploading,
  processing,
  ready,
  failed,
  deleted,
  rejected,
  unknown,
}

extension SocialProcessingStatusX on SocialProcessingStatus {
  /// Whether playback is permitted for this status.
  bool get allowsPlayback => this == SocialProcessingStatus.ready;

  /// Whether the item may appear in public feeds.
  bool get isPublicEligible => this == SocialProcessingStatus.ready;

  /// Whether this is a creator-only state (drafts/uploads/processing/failed).
  bool get isCreatorOnly =>
      this == SocialProcessingStatus.draft ||
      this == SocialProcessingStatus.uploading ||
      this == SocialProcessingStatus.processing ||
      this == SocialProcessingStatus.failed;

  static SocialProcessingStatus parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'draft':
        return SocialProcessingStatus.draft;
      case 'uploading':
      case 'upload':
      case 'pending_upload':
        return SocialProcessingStatus.uploading;
      case 'processing':
      case 'inprogress':
      case 'in_progress':
      case 'queued':
      case 'pendingupload':
        return SocialProcessingStatus.processing;
      case 'ready':
      case 'published':
      case 'live':
      case 'ready_to_stream':
        return SocialProcessingStatus.ready;
      case 'failed':
      case 'error':
        return SocialProcessingStatus.failed;
      case 'deleted':
        return SocialProcessingStatus.deleted;
      case 'rejected':
      case 'blocked':
        return SocialProcessingStatus.rejected;
      case '':
        // Legacy rows carry no processingStatus. Treat as ready so existing R2
        // content keeps playing; the URL-level guards still protect posters.
        return SocialProcessingStatus.ready;
      default:
        return SocialProcessingStatus.unknown;
    }
  }
}

/// Returns true when [url] is a streaming manifest (HLS `.m3u8` / DASH `.mpd`)
/// or an obvious video file that must never be handed to an image widget.
bool isStreamingManifestUrl(String? url) {
  final value = (url ?? '').trim().toLowerCase();
  if (value.isEmpty) return false;
  // Strip query string before checking the extension.
  final path = value.split('?').first;
  return path.endsWith('.m3u8') ||
      path.endsWith('.mpd') ||
      value.contains('format=hls') ||
      value.contains('/manifest/') ||
      path.endsWith('.ts');
}

/// Returns true when [url] looks like a raw video file (playback-only).
bool isVideoFileUrl(String? url) {
  final path = (url ?? '').trim().toLowerCase().split('?').first;
  if (path.isEmpty) return false;
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.mkv');
}

/// Debug-only guard. Throws in debug builds if a video/manifest URL is about to
/// be used as an image source, so the mistake is caught in tests and dev before
/// it ever ships. In release builds it is a no-op (the UI degrades gracefully
/// to a placeholder instead of crashing users).
void assertNotStreamingManifest(String? url, {String context = 'image'}) {
  assert(() {
    if (isStreamingManifestUrl(url)) {
      throw FlutterError(
        'Media contract violation: a streaming manifest URL was passed to an '
        'image widget ($context).\nURL: $url\n'
        'posterImageUrl must be a still image; use videoPlaybackUrl with a '
        'video player instead.',
      );
    }
    if (isVideoFileUrl(url)) {
      throw FlutterError(
        'Media contract violation: a video file URL was passed to an image '
        'widget ($context).\nURL: $url\n'
        'Use a generated thumbnail/poster for the image slot.',
      );
    }
    return true;
  }());
}

@immutable
class SocialMediaPresentation {
  const SocialMediaPresentation({
    required this.mediaAssetId,
    required this.provider,
    required this.mediaKind,
    required this.playbackType,
    required this.videoPlaybackUrl,
    required this.posterImageUrl,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.processingStatus,
  });

  final int? mediaAssetId;
  final String? provider;
  final SocialMediaKind mediaKind;
  final SocialPlaybackType playbackType;

  /// URL for the video player only. Null when there is nothing playable.
  final String? videoPlaybackUrl;

  /// URL for an image widget only. Guaranteed to never be a manifest/MP4.
  /// Null means "no poster available" → callers render the neutral Maslaki
  /// video placeholder (a missing poster must not block playback).
  final String? posterImageUrl;

  final int? width;
  final int? height;
  final int? durationMs;
  final SocialProcessingStatus processingStatus;

  bool get isReady => processingStatus.allowsPlayback;

  bool get hasVideo =>
      playbackType != SocialPlaybackType.none &&
      (videoPlaybackUrl?.trim().isNotEmpty ?? false);

  bool get hasPoster => posterImageUrl?.trim().isNotEmpty ?? false;

  /// Aspect ratio (width / height) when both dimensions are known, else null so
  /// callers fall back to a sensible default (9:16 for reels).
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// True when the media is vertical (portrait) or unknown — the default reel
  /// shape. False only when we positively know it is landscape/square.
  bool get isVertical {
    final ar = aspectRatio;
    if (ar == null) return true;
    return ar < 1.0;
  }

  /// Poster resolution order (§2.5):
  ///   thumbnailUrl → posterUrl → provider-generated thumbnail → null.
  /// Every candidate is filtered through the manifest guard so a playback URL
  /// can never leak into the poster slot.
  static String? _resolvePoster(SocialMediaAsset? asset, {String? provider}) {
    final candidates = <String?>[
      asset?.thumbnailUrl,
      asset?.posterUrl,
      _providerThumbnail(asset, provider),
    ];
    for (final candidate in candidates) {
      final value = (candidate ?? '').trim();
      if (value.isEmpty) continue;
      // Defensive: never surface a manifest/MP4 as a poster even if the backend
      // mislabels it.
      if (isStreamingManifestUrl(value) || isVideoFileUrl(value)) continue;
      return value;
    }
    return null;
  }

  /// Cloudflare Stream can synthesize a thumbnail from the stream UID. This is a
  /// provider-generated *image*, safe for the poster slot.
  static String? _providerThumbnail(SocialMediaAsset? asset, String? provider) {
    final uid = (asset?.streamUid ?? '').trim();
    final prov = (provider ?? asset?.provider ?? '').trim().toLowerCase();
    if (uid.isEmpty) return null;
    if (prov.contains('cloudflare') || prov.contains('stream')) {
      return 'https://videodelivery.net/$uid/thumbnails/thumbnail.jpg';
    }
    return null;
  }

  /// Playback resolution order (§2.6):
  ///   playbackUrl → normalized legacy video URL → none.
  static ({String? url, SocialPlaybackType type}) _resolvePlayback(
    SocialMediaAsset? asset,
    SocialMediaKind kind,
  ) {
    if (kind != SocialMediaKind.reel && kind != SocialMediaKind.video) {
      return (url: null, type: SocialPlaybackType.none);
    }
    final playback = (asset?.playbackUrl ?? '').trim();
    if (playback.isNotEmpty) {
      return (
        url: playback,
        type: isStreamingManifestUrl(playback)
            ? SocialPlaybackType.hls
            : SocialPlaybackType.progressiveMp4,
      );
    }
    final legacy = (asset?.normalizedUrl ?? '').trim();
    if (legacy.isNotEmpty) {
      return (
        url: legacy,
        type: isStreamingManifestUrl(legacy)
            ? SocialPlaybackType.hls
            : SocialPlaybackType.progressiveMp4,
      );
    }
    return (url: null, type: SocialPlaybackType.none);
  }

  static SocialMediaKind _kindFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'reel':
        return SocialMediaKind.reel;
      case 'video':
        return SocialMediaKind.video;
      case 'image':
      case 'photo':
        return SocialMediaKind.image;
      case 'text':
        return SocialMediaKind.text;
      default:
        return SocialMediaKind.unknown;
    }
  }

  /// Builds a presentation from a raw [SocialMediaAsset] and a media-kind hint.
  factory SocialMediaPresentation.fromAsset(
    SocialMediaAsset? asset, {
    required SocialMediaKind kind,
    int? width,
    int? height,
  }) {
    final playback = _resolvePlayback(asset, kind);
    return SocialMediaPresentation(
      mediaAssetId: asset?.id,
      provider: asset?.provider,
      mediaKind: kind,
      playbackType: playback.type,
      videoPlaybackUrl: playback.url,
      posterImageUrl: _resolvePoster(asset, provider: asset?.provider),
      width: width,
      height: height,
      durationMs: asset?.durationMs,
      processingStatus:
          SocialProcessingStatusX.parse(asset?.processingStatus),
    );
  }

  /// Builds a presentation for a [SocialPost] (feed / reel item).
  factory SocialMediaPresentation.fromPost(SocialPost post) {
    final kind = _kindFromString(normalizeSocialPostMediaClass(post));
    final gallery =
        post.mediaGallery.isNotEmpty ? post.mediaGallery.first : null;
    final asset = gallery?.asset ?? post.asset;
    return SocialMediaPresentation.fromAsset(asset, kind: kind);
  }

  /// An explicitly-empty presentation (no media / fully unavailable).
  static const SocialMediaPresentation empty = SocialMediaPresentation(
    mediaAssetId: null,
    provider: null,
    mediaKind: SocialMediaKind.unknown,
    playbackType: SocialPlaybackType.none,
    videoPlaybackUrl: null,
    posterImageUrl: null,
    width: null,
    height: null,
    durationMs: null,
    processingStatus: SocialProcessingStatus.unknown,
  );
}
