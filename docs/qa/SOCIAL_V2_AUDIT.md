# Social V2 Audit

## Scope

This audit covers the release-closure work that was proven in this branch:

- new Reel / Story video storage and playback contract
- gallery-first social publishing entry flow
- Story viewer progression and lifecycle handling
- Reel preview / feed / share propagation of normalized media metadata

The broader building / moderation / messaging / deep-link surfaces were not rewritten in this pass and remain governed by the existing baseline and test coverage.

## Root Causes Found

### 1. Story progress and navigation were rebuild-sensitive

The previous story viewer path could restart or duplicate the current item when the widget tree rebuilt. The new viewer now uses a flattened timeline, explicit indices, and a single progress controller so rebuilds do not reset the current item.

### 2. New social videos did not carry a stable playback contract

Reels and Stories were still consumed as generic media assets, so Flutter could not reliably distinguish:

- storage provider
- playback URL
- poster / thumbnail URL
- processing state

The backend now persists provider-aware asset fields and the Flutter models prefer Stream playback for new video uploads.

### 3. Gallery-first publishing used the wrong picker primitive

The publishing flow previously went through a general picker path. The new flow uses the device gallery path first, which matches the social publishing expectation and avoids document-style selection for normal social media uploads.

### 4. Share-to-story needed to reference the original Reel

The share draft now points to the original reel playback/poster asset rather than re-uploading the same media into a new file path.

## Reproduced / Verified

- Stream-backed social asset rows persist provider and playback fields
- Story viewer advances across stories and users
- Social contract models parse normalized media fields
- Gallery-first picker returns path-backed media items in order

## Current Blockers

- Real-device verification is still required for foreground/background/killed notifications and deep-link taps.
- The wider building / moderation / deep-link / messaging surfaces were not changed by this release-closure pass.

