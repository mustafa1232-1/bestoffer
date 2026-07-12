# Release Candidate Checklist

## Phase 3C Closeout

- [x] Migration 132 integrity audited against the repo, local QA DB, and Railway
- [x] Security re-audit completed
- [x] Bounded performance baseline smoke completed locally
- [x] Android APK/AAB manifest and signing verified
- [x] Release artifacts built for user, store, delivery, captain, pharmacy, and company
- [x] `flutter analyze` passed in the current closure stream
- [x] `flutter test` passed in the current closure stream
- [x] `cd backend && npm test` passed in the current closure stream
- [x] `cd backend && npm run verify:release:local` passed in the current closure stream
- [x] `cd backend && railway run --service bestoffer npm run verify:release:runtime` passed in the current closure stream
- [ ] Real-device push/background/killed-app and notification-tap QA remains blocked
- [ ] Full `permissions:check` role matrix remains blocked until user / owner / delivery credentials are present in QA env

## Release Candidate Status

- Overall status: `PASS_RUNTIME_RC_BUILT_DEVICE_PENDING`
- Not ready for internal testing until the real-device QA gate is satisfied.
