# Social V2 Architecture

## High-Level Direction

- New Reel and Story videos use Cloudflare Stream.
- Images, attachments, and legacy read-only videos remain on R2.
- Flutter consumes one normalized media contract instead of inferring state from raw URLs.

## Media Asset Contract

The canonical client-facing asset shape now includes:

- `provider`
- `streamUid`
- `normalizedUrl`
- `posterUrl`
- `playbackUrl`
- `thumbnailUrl`
- `durationMs`
- `processingStatus`

## Flow Summary

1. User selects media from the gallery-first picker.
2. Backend prepares the asset.
3. New video uploads route to Stream.
4. Backend stores provider-aware playback metadata.
5. Flutter renders the correct poster and playback URL.
6. Story/Reel viewer uses the normalized asset contract for playback and sharing.

## Compatibility Rules

- Legacy R2 video playback remains read-only.
- New uploads must not silently fall back to R2.
- UI should prefer `thumbnailUrl` and `playbackUrl` when present.

