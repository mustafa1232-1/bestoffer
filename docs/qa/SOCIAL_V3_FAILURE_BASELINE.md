# Social V3 — Failure Baseline

The device screenshot supplied with the remediation brief is the **failure
baseline**. This document explains every marked problem and the root cause where
one has been positively identified in code.

## The baseline screenshot (Arabic "الرئيسية" tab)

The installed app renders a "reel" as an **old feed card**, not a full-screen
reel. Observed defects:

| # | Marked problem | Status of root-cause |
|---|----------------|----------------------|
| 1 | Reel shown as an old rounded feed card in the Reels/feed surface | Old widget tree (`SocialPostCardV2` / `SocialReelCard`) rendered inside the reels/feed path |
| 2 | Broken / invalid **circular** media placeholder (large empty dark circle) | **Root cause found** — a video playback URL was being resolved as a *poster image URL* and handed to `CachedAppImage`, which then failed to decode (a manifest/MP4 is not an image) and collapsed into the empty circular avatar-style placeholder |
| 3 | Reaction chips (`0▶ 0🔖 0💬 0❤`) rendered **below** the media | Feed-card layout — reaction row belongs under a post card, not on a full-screen reel |
| 4 | A separate share icon below the content | Feed-card affordance, not the reel action rail |
| 5 | A floating "إنشاء +" (Create) button overlapping content | Global FAB from the feed shell drawn over the reel |
| 6 | A normal header + bottom navigation framing the reel | The reel was hosted inside the normal app shell, not a full-screen route |
| 7 | No full-screen Reel experience | No dedicated full-screen reel viewer was the active route |
| 8 | No full-screen Reel-to-Story experience | Shared reels rendered as a fixed-width attachment card |

## Root cause of the broken / circular poster (defect #2)

In `packages/social_core/lib/src/models/social_models.dart`,
`resolveSocialPostPosterUrl()` resolves a poster for a post. The **asset
branch** correctly refuses to use a playback URL as a poster for video posts:

```dart
final assetUrl = (post.asset?.playbackUrl ?? post.asset?.normalizedUrl ?? '').trim();
if (assetUrl.isNotEmpty && !isSocialVideoPost(post)) return assetUrl;  // guarded
```

But the **gallery branch** immediately above it returns the gallery item's
`playbackUrl` as a poster with **no `!isSocialVideoPost` guard**:

```dart
final galleryUrl = (galleryFirst?.asset?.playbackUrl
        ?? galleryFirst?.asset?.normalizedUrl
        ?? galleryFirst?.mediaUrl ?? '').trim();
if (galleryUrl.isNotEmpty) return galleryUrl;   // <-- can be an HLS .m3u8 / MP4
```

For a reel whose gallery asset has a `playbackUrl` (Cloudflare Stream HLS) but no
`thumbnailUrl`/`posterUrl` yet, this returns the **HLS manifest URL as the
poster**. That string is then passed to `CachedAppImage`, which cannot decode a
`.m3u8`/MP4 as an image → the broken, empty circular placeholder.

## How Social V3 makes this defect structurally impossible

The V3 media contract (`lib/features/social_v3/media/`) separates the two URL
roles at the type level:

* `SocialMediaPresentation.posterImageUrl` — only ever an image; every candidate
  is filtered through `isStreamingManifestUrl` / `isVideoFileUrl`, so a
  manifest/MP4 can never occupy the poster slot. If no real poster exists the
  field is `null` and the UI shows the neutral Maslaki placeholder.
* `SocialMediaPresentation.videoPlaybackUrl` — only ever consumed by a video
  player.
* `SocialSafeImage` — the single image entry point — runs
  `assertNotStreamingManifest()` (throws in debug/tests) and, in release,
  degrades a bad URL to the placeholder instead of a broken box.
* The circular shape is gone: the reel surface uses `ClipRect` + `BoxFit.cover`,
  never `ClipOval`/`CircleAvatar`.

See `test/features/social_v3/social_media_contract_test.dart` for the tests that
prove an HLS URL never reaches `CachedAppImage`, and
`test/features/social_v3/reels_v3_regression_test.dart` for the layout
regression guards (no AppBar, no Card, no `ClipOval`, vertical pager).
