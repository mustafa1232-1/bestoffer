# Social V2 API Contract

## Canonical Asset Fields

Backend responses that include media assets should expose the following stable fields when available:

- `provider`
- `streamUid`
- `playbackUrl`
- `thumbnailUrl`
- `normalizedUrl`
- `durationMs`
- `processingStatus`

## Response Rules

- New video uploads should report Stream-backed playback data.
- Legacy rows without Stream fields should continue to hydrate from fallback media URLs.
- A consumer must not guess playback URLs from an upload path.
- A consumer must not infer a publish state from a missing field alone.

## Current Implementation Notes

- `social_media_asset` now stores provider and playback metadata.
- Story / Reel model parsing prefers the normalized asset fields.
- Story share drafts prefer the original reel asset reference.

