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

### Regression Test

- `test/language/api_error_mapper_test.dart`
  - Added coverage for the owner-already-linked error in both English and Arabic.

## Root Cause

The backend already returned a structured error for a second store attempt:

- `OWNER_ALREADY_HAS_MERCHANT`

The issue was in the shared Flutter error mapping path. That code was missing from `api_error_mapper.dart`, so the flow degraded to the generic fallback message instead of the intended clear Arabic explanation.

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
  - passed, 249 tests
- `cd backend && npm run verify:release:local`
  - passed
- targeted backend tests for the Phase 1A scope
  - passed, 19 tests

## Phase 1A Audit Summary

The audit matrix has been expanded with explicit Phase 1A rows for:

- second store creation
- fashion taxonomy separation
- merchant coupons
- admin coupons

The matrix now contains 23 rows total.

## Current P0 Snapshot

| Blocker | Status | Notes |
|---|---|---|
| Second store creation returns only `فشل` | REPRODUCED | The root cause was the missing shared error mapping for `OWNER_ALREADY_HAS_MERCHANT`. |
| Men/women fashion leakage | NOT_YET_REPRODUCED | Backend tests exist; live create/list/search proof still pending. |
| Missing category visibility | NOT_YET_REPRODUCED | Backend taxonomy and cache invalidation are already covered by tests. |
| Missing product visibility | NOT_YET_REPRODUCED | Backend authoring and hidden-product tests exist; live proof still pending. |
| Merchant/admin coupon failure | PARTIALLY_REPRODUCED | Backend scope tests exist for merchant/admin coupon scope separation. |

## Deliverable State

- Phase 1A documentation is now separated from the Phase 0 baseline.
- Phase 1A checkpoint commit `6dd5136` has been created.
- The remaining worktree must be kept clean after this checkpoint.
- No destructive data or schema action was performed.
