# Security Re-Audit Report

Phase 3C security and dependency review for the release-candidate closeout.

## Scope

- Auth and surface isolation
- Session / token lifecycle sanity
- Upload and deep-link contract review
- Secret / credential review
- Dependency freshness review
- Permissions matrix availability

## Results

| Check | Result | Notes |
|---|---|---|
| `backend/src/scripts/securitySelfCheck.js` | PASS | `active_locked_users: 0`, `findings: 0` |
| `railway run --service bestoffer npm run verify:release:runtime` | PASS | The release runtime chain still includes the security runtime stage and passed. |
| Auth / surface isolation | PASS | Customer-to-admin remains `403`, owner-to-delivery remains `403`, delivery-to-owner remains `403`, and super-admin user-surface login still resolves to a valid super-admin shell. |
| Anonymous protection | PASS | Anonymous access to protected admin routes still returns `401`. |
| Header / firewall checks | PASS | `/ready` and protected upload responses still return the expected security headers. |
| Secret scan | PASS | No hardcoded production secrets or private keys were found in tracked code. Public Firebase API keys are present in client config files, and `backend/.env.example` only contains placeholder private-key examples. |
| Backend dependency review | PASS_WITH_UPDATES | `npm outdated --json` reported 14 direct backend packages with newer wanted/latest versions. No release blocker was introduced by this audit. |
| Flutter dependency review | PASS_WITH_UPDATES | `flutter pub outdated` reported 58 upgradable dependencies locked in `pubspec.lock` and 14 packages constrained below a resolvable version. No release blocker was introduced by this audit. |
| `permissions:check` full role matrix | BLOCKED | `backend/.env.test` only contains `SUPER_ADMIN_PHONE` / `SUPER_ADMIN_PIN`, and `backend/.env` only contains `DEV_ADMIN_PHONE` / `DEV_ADMIN_PIN`. This QA environment does not currently provide user / owner / delivery credentials, so the role matrix cannot complete here. |

## Security Notes

- The known `FORBIDDEN_APP_SURFACE` guard remains intact for super-admin login outside the allowed surface.
- The runtime security check still proves strict `401` vs `403` behavior for authenticated and unauthenticated paths.
- The secret scan only surfaced expected Firebase client API keys and placeholder values in example env files.

## Conclusion

- No new security regression was found in Phase 3C.
- The only remaining blocker in this area is lack of complete QA credentials for the standalone `permissions:check` script.
