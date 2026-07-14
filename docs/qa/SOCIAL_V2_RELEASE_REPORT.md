# Social V2 Release Report

## Summary

The branch now includes the core release-closure work for the proven media pipeline and Story/Reel viewer issues:

- Stream-backed media asset persistence
- normalized media contract in Flutter
- gallery-first publishing picker
- rebuild-safe story timeline viewer
- Stream-aware reel/story playback and sharing helpers
- real user APK build for the current closure snapshot

## Files Changed

### Backend

- `backend/src/config/env.js`
- `backend/src/modules/feed/feed.controller.js`
- `backend/src/modules/feed/feed.media.service.js`
- `backend/src/modules/feed/feed.product.mappers.js`
- `backend/src/modules/feed/feed.repo.js`
- `backend/src/modules/feed/feed.service.js`
- `backend/src/shared/utils/cloudflare-stream.js`
- `backend/src/tests/social.media.stream-asset.test.js`
- `backend/sql/134_social_media_stream_asset.sql`

### Flutter / Shared Dart

- `lib/core/files/media_picker_service.dart`
- `lib/features/social/data/social_stream_upload_service.dart`
- `lib/features/social/state/social_controller.dart`
- `lib/features/social/ui/social_explore_screen.dart`
- `lib/features/social/ui/social_feed_screen.dart`
- `lib/features/social/ui/social_reel_viewer_screen.dart`
- `lib/features/social/ui/social_share_sheet.dart`
- `lib/features/social/ui/social_story_quick_viewer.dart`
- `lib/features/social/ui/social_story_viewer_screen.dart`
- `lib/features/social/ui/widgets/social_post_card_v2.dart`
- `lib/features/social/ui/widgets/social_reel_card.dart`
- `packages/social_core/lib/src/models/social_models.dart`
- `packages/social_core/lib/src/models/social_story_document.dart`
- `test/features/social/social_media_contract_test.dart`
- `test/social/social_story_quick_viewer_test.dart`

## Migration

- `134_social_media_stream_asset.sql`

## Root Cause Summary

1. Social video playback lacked provider-aware asset metadata, so the UI could not tell Stream-backed media from legacy R2 content reliably.
2. Gallery publishing used a generic file-picker path instead of a gallery-first media picker.
3. Story progression could restart or desync on rebuild instead of keeping a deterministic timeline state.
4. Reel/story sharing needed to reference the original normalized asset instead of re-uploading or losing the source relationship.
5. Story quick-viewer coverage needed a public screen wrapper so the render/test contract could be exercised without route-plumbing ambiguity.

## Test Results

- `flutter analyze` - PASS
- `flutter test` - PASS, 435 tests
- `cd backend && npm test` - PASS, 284 tests
- `cd backend && npm run verify:release:local` - PASS
- `cd backend && railway run --service bestoffer npm run verify:release:runtime` - BLOCKED by `orderE2ECheck.js` returning `401 INVALID_TOKEN` at the owner order-preparing step after the auth/session and realtime subchecks passed

## Build Results

- Android user release APK built successfully
- Artifact: `build/app/outputs/flutter-apk/app-user-release.apk`
- iOS release build: NOT TESTED in this workspace

## Device Results

- Android device availability: BLOCKED (`adb` not available on this machine)
- Foreground/background/killed notification verification: BLOCKED
- Deep-link tap verification: BLOCKED

## Remaining Blocked Items

- `orderE2ECheck.js` needs a separate auth-token investigation before the full Railway runtime chain can be promoted to PASS
- Real-device validation for push and tap flows
- Any broader social subsystems not touched in this closure pass
