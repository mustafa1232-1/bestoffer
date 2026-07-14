# Social V3 — Media Contract (§2)

Source: `lib/features/social_v3/media/social_media_presentation.dart`
Guard widget: `lib/features/social_v3/media/social_safe_image.dart`
Tests: `test/features/social_v3/social_media_contract_test.dart`

## Types

`SocialMediaPresentation` is the single view-model for presenting social media.

| Field | Role |
|-------|------|
| `mediaAssetId`, `provider` | identity |
| `mediaKind` | `reel` / `video` / `image` / `text` / `unknown` |
| `playbackType` | `hls` / `progressiveMp4` / `none` |
| `videoPlaybackUrl` | **video player only** |
| `posterImageUrl` | **image widget only** — guaranteed never a manifest/MP4 |
| `width`, `height`, `aspectRatio`, `isVertical` | layout |
| `durationMs` | playback |
| `processingStatus` | lifecycle (see below) |

## Hard rules (enforced)

1. `videoPlaybackUrl` is used only by a video player.
2. `posterImageUrl`/poster slots are used only by image widgets.
3. `.m3u8`, `format=hls`, DASH `.mpd`, `.ts`, and raw video files are never
   passed to `CachedAppImage`. `SocialSafeImage` asserts this in debug and
   degrades gracefully in release.
4. A playback URL is never used as a poster fallback.
5. **Poster selection order:** `thumbnailUrl → posterUrl → provider-generated
   thumbnail (Cloudflare `videodelivery.net/<uid>/thumbnails/thumbnail.jpg`) →
   null → neutral Maslaki placeholder`.
6. **Playback selection order:** `playbackUrl → normalized legacy video URL →
   none`.
7. A missing poster does not block playback.
8. A missing playback URL does not fake a successful video state
   (`playbackType == none`, `hasVideo == false`).

## Processing status → presentation (§2.9)

`SocialProcessingStatus`: `draft`, `uploading`, `processing`, `ready`, `failed`,
`deleted`, `rejected`, `unknown`.

| Status | Public feed | Playback | Creator surface |
|--------|-------------|----------|-----------------|
| draft | no | no | Drafts |
| uploading | no | no | Upload progress |
| processing | no | no | "جاري تجهيز الفيديو" |
| ready / published | yes | yes | plays |
| failed | no | no | retry/details |
| deleted / rejected | no | no | hidden from public feeds |

Legacy rows with an empty `processingStatus` are treated as `ready` so existing
R2 content keeps playing; the URL-level guards still protect the poster slot.

## Debug assertion

`assertNotStreamingManifest(url)` throws a `FlutterError` in debug/test builds
when a manifest or video-file URL is about to be used as an image, and is a
no-op in release. `SocialSafeImage` calls it before delegating to
`CachedAppImage`.
