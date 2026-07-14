# Social V2 Media Pipeline

## Storage Split

- Cloudflare Stream: new Reel and Story videos.
- Cloudflare R2: images, attachments, and legacy read-only videos.

## Lifecycle

The implemented media lifecycle uses explicit progression:

- draft
- uploading
- processing
- ready
- published
- failed

## Backend Behavior

- Stream upload happens before the media record is finalized.
- The record persists provider-aware playback data.
- Temporary source files are cleaned up after successful persistence.
- Legacy rows keep working through fallback playback URLs.

## Flutter Behavior

- Gallery-first selection returns path-backed media files.
- Story and Reel views prefer the normalized asset fields.
- Posters fall back cleanly when the thumbnail is missing.

