# Social V2 Test Matrix

## Automated Tests Added

- `test/features/social/social_media_contract_test.dart`
- `test/social/social_story_quick_viewer_test.dart`
- `backend/src/tests/social.media.stream-asset.test.js`

## Verified Behavior

- Stream-backed assets parse with the new provider-aware fields.
- Story viewer advances across stories and users.
- Gallery-first media selection preserves order and path-backed files.
- Stream asset rows persist playback metadata in PostgreSQL.

## Verification Commands

- `flutter analyze`
- `flutter test`
- `cd backend && npm test`
- `cd backend && npm run verify:release:local`

## Remaining Gaps

- `cd backend && npm run verify:release:runtime` is blocked from this workstation by Railway proxy connectivity.
- Real-device notification and deep-link tap validation is blocked because no Android device is connected to this machine.

