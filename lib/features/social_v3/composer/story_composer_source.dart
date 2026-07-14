import 'package:flutter/foundation.dart';

import '../domain/story_view_data.dart';
import '../media/social_media_presentation.dart';

/// What a story is being composed from (§6/§7).
enum StorySourceKind { localImage, localVideo, sharedReel, sharedPost, text }

/// Whether the backend persists & enforces **story-level** audience scope.
///
/// SAFETY GUARD: the backend `validateCreateStory` + story service currently
/// ignore story scope (only `social_post` has an `audience_scope` column), so a
/// building/block/compound story would be published **globally**. Until the
/// story-scope migration + service ship, this is `false` and the composer
/// **blocks** non-global story publication instead of silently going global.
/// Flip to `true` (or wire to the backend capability) once the feature lands.
const bool kStoryAudienceScopeSupported = false;

/// Publishing audience scope for a story (§2). The authoritative value is
/// re-validated by the backend against the user's permissions — Flutter never
/// decides authorization.
enum StoryAudienceScope {
  global,
  followers,
  friends,
  closeFriends,
  area,
  compound,
  block,
  building,
  custom,
}

extension StoryAudienceScopeX on StoryAudienceScope {
  /// The backend `audienceScopeType` string.
  String get wireType {
    switch (this) {
      case StoryAudienceScope.global:
        return 'global';
      case StoryAudienceScope.followers:
        return 'followers';
      case StoryAudienceScope.friends:
        return 'friends';
      case StoryAudienceScope.closeFriends:
        return 'close_friends';
      case StoryAudienceScope.area:
        return 'area';
      case StoryAudienceScope.compound:
        return 'compound';
      case StoryAudienceScope.block:
        return 'block';
      case StoryAudienceScope.building:
        return 'building';
      case StoryAudienceScope.custom:
        return 'custom';
    }
  }

  static StoryAudienceScope fromWire(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'followers':
        return StoryAudienceScope.followers;
      case 'friends':
        return StoryAudienceScope.friends;
      case 'close_friends':
        return StoryAudienceScope.closeFriends;
      case 'area':
        return StoryAudienceScope.area;
      case 'compound':
        return StoryAudienceScope.compound;
      case 'block':
        return StoryAudienceScope.block;
      case 'building':
        return StoryAudienceScope.building;
      case 'custom':
        return StoryAudienceScope.custom;
      default:
        return StoryAudienceScope.global;
    }
  }
}

/// Immutable publishing-scope context carried by the composer.
@immutable
class StoryComposerScope {
  const StoryComposerScope({
    required this.scope,
    this.scopeCode,
    this.label,
    this.isOfficial = false,
    this.locked = false,
  });

  final StoryAudienceScope scope;

  /// Building/block/compound/area identifier (backend `audienceScopeCode`).
  final String? scopeCode;
  final String? label;

  /// Whether this is an official building/community story (needs a privileged
  /// role, enforced by the backend).
  final bool isOfficial;

  /// When true the user cannot change the preselected scope (e.g. opened from a
  /// specific building context).
  final bool locked;

  static const StoryComposerScope global =
      StoryComposerScope(scope: StoryAudienceScope.global);
}

/// Reference to a shared reel used as a story's **base media** (never an
/// attachment card). The reel video is not duplicated — only a reference plus
/// visual layout metadata is stored.
@immutable
class SharedReelSource {
  const SharedReelSource({
    required this.reelId,
    required this.originalOwnerId,
    required this.playbackUrl,
    required this.thumbnailUrl,
    required this.posterUrl,
    required this.width,
    required this.height,
    required this.caption,
    required this.available,
  });

  final int reelId;
  final int originalOwnerId;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final String? posterUrl;
  final int? width;
  final int? height;
  final String caption;
  final bool available;

  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 9 / 16;
    return w / h;
  }

  bool get isVertical => aspectRatio < 1.0;

  /// The presentation used to render the reel as the story base media. Poster
  /// slot is guarded (never the playback URL).
  SocialMediaPresentation toPresentation() => SocialMediaPresentation(
        mediaAssetId: reelId,
        provider: 'cloudflare_stream',
        mediaKind: SocialMediaKind.reel,
        playbackType: (playbackUrl ?? '').isEmpty
            ? SocialPlaybackType.none
            : (isStreamingManifestUrl(playbackUrl)
                ? SocialPlaybackType.hls
                : SocialPlaybackType.progressiveMp4),
        videoPlaybackUrl: playbackUrl,
        posterImageUrl: _guardedPoster(),
        width: width,
        height: height,
        durationMs: null,
        processingStatus: available
            ? SocialProcessingStatus.ready
            : SocialProcessingStatus.deleted,
      );

  String? _guardedPoster() {
    for (final candidate in [thumbnailUrl, posterUrl]) {
      final value = (candidate ?? '').trim();
      if (value.isEmpty) continue;
      if (isStreamingManifestUrl(value) || isVideoFileUrl(value)) continue;
      return value;
    }
    return null;
  }

  factory SharedReelSource.fromReelRef(SharedReelRef ref) => SharedReelSource(
        reelId: ref.reelId,
        originalOwnerId: 0,
        playbackUrl: null,
        thumbnailUrl: null,
        posterUrl: null,
        width: null,
        height: null,
        caption: ref.caption ?? '',
        available: true,
      );
}

/// A local file chosen from the gallery for a story.
@immutable
class LocalStoryMedia {
  const LocalStoryMedia({
    required this.path,
    required this.isVideo,
    required this.width,
    required this.height,
  });

  final String path;
  final bool isVideo;
  final int? width;
  final int? height;
}

/// The immutable source description handed to the composer.
@immutable
class StoryComposerSource {
  const StoryComposerSource._({
    required this.kind,
    this.sharedReel,
    this.localMedia,
    this.text,
  });

  final StorySourceKind kind;
  final SharedReelSource? sharedReel;
  final LocalStoryMedia? localMedia;
  final String? text;

  factory StoryComposerSource.sharedReel(SharedReelSource reel) =>
      StoryComposerSource._(
        kind: StorySourceKind.sharedReel,
        sharedReel: reel,
      );

  factory StoryComposerSource.localImage(LocalStoryMedia media) =>
      StoryComposerSource._(kind: StorySourceKind.localImage, localMedia: media);

  factory StoryComposerSource.localVideo(LocalStoryMedia media) =>
      StoryComposerSource._(kind: StorySourceKind.localVideo, localMedia: media);

  factory StoryComposerSource.text(String value) =>
      StoryComposerSource._(kind: StorySourceKind.text, text: value);

  /// True when the source reel/media is locked (not manually resizable) —
  /// shared reels are locked by default (§6).
  bool get isSourceLocked => kind == StorySourceKind.sharedReel;
}
