# Phase 1C Auth / Session / Push Report

## Scope

- User app
- Store app
- Delivery app
- Captain app
- Backend auth, session, push-token, realtime-token, and shell gating

## Outcome

- Runtime verification passed on Railway.
- Local verification passed.
- Flutter analysis and Flutter tests passed.
- The remaining gap is real-device push/background/killed-app validation.
- Checkpoint commit: `3c56dfd`

## What Was Proven

- Guest requests to `/api/realtime/token` and `/api/notifications/push-token` now fail with `NO_TOKEN` without triggering terminal session invalidation.
- `login` / `register` / `refresh` / `logout` / `logout-all` flows remain stable under the shared session invalidation coordinator.
- `super_admin` login on the user surface returns a valid authenticated shell with `isSuperAdmin=true`.
- `super_admin` is blocked on a non-permitted surface during login.
- Owner, customer, delivery, and captain sessions all survive login, refresh, push-token sync, and realtime-token issuance.
- `logout-all` revokes the second live session cleanly and the invalidated session returns `401 INVALID_TOKEN`.
- Push token registration and unregistration work after authentication.
- Realtime token issuance is skipped for guests and resumes after successful auth.

## Verification

- `flutter analyze`
- `flutter test`
- `cd backend && npm test`
- `cd backend && npm run verify:release:local`
- `cd backend && railway run --service bestoffer npm run verify:release:runtime`

## Runtime Evidence

- `backend/src/scripts/securityRuntimeCheck.js`
- `backend/src/scripts/realtimeRuntimeCheck.js`
- `backend/src/scripts/authSessionPushE2ECheck.js`

## Notes

- The earlier company-surface expectation in the auth/session E2E was a script mismatch, not a runtime regression.
- Real-device push/background/killed-app proof remains pending and is still marked blocked in the QA docs.
