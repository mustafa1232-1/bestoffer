# Phase 1A Report - Store / Catalog / Coupon

## Scope

Phase 1A covers the P0 launch-blocker slice for:

- second store creation failure
- men / women fashion leakage
- missing category visibility
- missing product visibility
- merchant-created coupons
- admin-created coupons

No orders, delivery, taxi, social, Kysely, or unrelated business logic was changed in this phase.

## Code Change

### Flutter

- `lib/core/network/api_error_mapper.dart`
  - Added a shared translation for `OWNER_ALREADY_HAS_MERCHANT` so second store creation no longer falls through to a generic `فشل`.

### Backend

- `backend/src/modules/merchants/merchants.controller.js`
- `backend/src/modules/merchants/merchants.repo.js`
  - Added department-aware browse cache keys so men / women fashion list responses no longer reuse the same cached payload.

### Regression Test

- `test/language/api_error_mapper_test.dart`
  - Added coverage for the owner-already-linked error in both English and Arabic.
- `backend/src/tests/merchants.store-department.test.js`
  - Added cache-key separation coverage for fashion browse responses.

## Root Cause

The backend already returned a structured error for a second store attempt:

- `OWNER_ALREADY_HAS_MERCHANT`

The issue was in the shared Flutter error mapping path. That code was missing from `api_error_mapper.dart`, so the flow degraded to the generic fallback message instead of the intended clear Arabic explanation.

The fashion leakage was a separate backend browse-cache bug. Both the Redis browse key and the controller hot-cache key omitted `department`, so the women browse request could reuse the men payload. That is now fixed by making the cache keys department-aware and bumping the browse cache schema version.

## Verification

### Flutter

- `flutter analyze`
  - passed
- `flutter test`
  - passed, 371 tests
- targeted Flutter regression tests
  - passed, 19 tests

### Backend

- `cd backend && npm test`
  - passed, 251 tests
- `cd backend && npm run verify:release:local`
  - passed
- `backend/src/scripts/storeCatalogCouponE2ECheck.js`
  - passed locally, 27 runtime steps
- `cd backend && railway run --service bestoffer npm run verify:release:runtime`
  - passed

## Phase 1A Audit Summary

The audit matrix has been expanded with explicit Phase 1A rows for:

- second store creation
- fashion taxonomy separation
- merchant coupons
- admin coupons

The matrix now contains 23 rows total.

The current continuation verified the full store/catalog/coupon slice at runtime:

- super admin login
- fashion department separation
- category create/list visibility
- product create/list visibility
- merchant coupon create/validate/preview/checkout
- admin coupon create/validate/preview/checkout

## Current P0 Snapshot

| Blocker | Status | Notes |
|---|---|---|
| Second store creation returns only `فشل` | PASS_RUNTIME | Live duplicate-owner smoke returns `OWNER_ALREADY_HAS_MERCHANT`; Flutter mapper regression is covered, but Store-app device smoke is still pending. |
| Men/women fashion leakage | PASS_RUNTIME | Live browse smoke now returns men + unisex for men and women + unisex for women after the department-aware cache fix. |
| Missing category visibility | PASS_RUNTIME | Live create/list smoke confirms category appears immediately on owner and public merchant lists. |
| Missing product visibility | PASS_RUNTIME | Live create/list smoke confirms product appears immediately on owner and public merchant lists. |
| Merchant/admin coupon failure | PASS_RUNTIME | Live merchant/admin coupon create/validate/preview/checkout smoke passed. |

## Deliverable State

- Phase 1A documentation is now separated from the Phase 0 baseline.
- Phase 1A checkpoint commit `558b989` has been created.
- The remaining worktree must be kept clean after this checkpoint.
- No destructive data or schema action was performed.
