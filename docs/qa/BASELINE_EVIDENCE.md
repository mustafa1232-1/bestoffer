# Baseline Evidence

Captured at the start of `Maslaki Full Application Closure Program` on the current repository state.

## Git Facts

- `HEAD`: `a5d342e0c5957d61ae4518b2eb69538fd70b1883`
- Branch: `release/maslaki-full-sync`
- Backup branch: `backup/pre-full-closure-20260711-045945`
- `git status --short`: clean
- `git diff --stat`: empty
- `git ls-files --others --exclude-standard`: empty

## Recent Commit Log

```text
a5d342e Refresh taxi and streams runtime checks
8253abe Prove multi-captain taxi offers in runtime E2E
bbdfe30 Stabilize taxi negotiation runtime checks
fb9038a Harden runtime logout revocation probe
976dd23 Allow super admin user-surface admin access
561ee85 Fix QA reset and taxi hardening
1e9ef0c Add order snapshot screen coverage
d6fbb54 Add order item snapshot regression tests
2c084ac Add order item snapshot UX v1
75f639e Bump Android release version codes
```

## Baseline Test Results

- `flutter analyze`: passed, no issues found
- `flutter test`: passed, 370 tests
- `cd backend && npm test`: passed, 249 tests
- `cd backend && npm run verify:release:local`: passed
- `cd backend && railway run --service bestoffer npm run verify:release:runtime`: passed

## Runtime / Deployment Health

- Production `/health`: `200`
- Production `/ready`: `200`
- Latest visible Railway deployment at capture time: `a6282bd1-1cb5-49c8-9e17-8d2a95d27c68 | SUCCESS`

## Current Build Status By Flavor

The workspace already contains release artifacts from the last verified build pass.

| Flavor | Release APK | Release AAB | Baseline status |
|---|---:|---:|---|
| user | present | present | verified artifact exists |
| store | present | present | verified artifact exists |
| delivery | present | present | verified artifact exists |
| captain | present | present | verified artifact exists |
| company | absent | absent | not present in current outputs |
| pharmacy | present | present | verified artifact exists |

## Notes

- No code changes were made before capturing this baseline.
- Real-device QA has not yet been executed in this phase, so killed-app push, background push, camera/location, and keyboard-safe manual flows remain device-blocked until a real device is connected.
- The repository already contains the order snapshot migration `backend/sql/131_order_item_display_snapshot.sql`; this baseline treats it as existing source of truth.
