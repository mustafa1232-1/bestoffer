# Store Production Closure Baseline

## Repository State
- Branch: `feat/store-production-closure`
- HEAD: `51765aa`
- Backup branch: `backup/pre-store-production-closure`
- Worktree: active on the original project root
- Dirty tree: present; numerous pre-existing modified and untracked files are intentionally preserved

## Safety Notes
- No `git reset`, `git clean`, or `git stash` was used.
- No unrelated changes were deleted.
- Baseline was captured on the current branch before any new store-closure edits in this session.

## Current High-Level Findings
- Coupon validation bug is reproducible in backend logs when SQL parameter typing is not explicit.
- The cart coupon failure manifested as `POST /api/coupons/validate -> 500` with PostgreSQL error `42P18` (`could not determine data type of parameter $3`).
- The coupon validation path now has an explicit typed join/cast fix in the working tree, and targeted coupon tests pass.
- Delivery/grouped-workflow tests are not green yet in the current baseline.

## Coupon Root Cause (Observed)
- Route used by the cart coupon flow: `POST /api/coupons/validate`
- Backend repo/service path:
  - `backend/src/modules/coupons/coupons.repo.js`
  - `backend/src/modules/coupons/coupons.service.js`
- Failure mode:
  - PostgreSQL could not infer the type of a nullable positional parameter used in coupon validation joins/checks.
  - Resulting error: `could not determine data type of parameter $3` (`42P18`)
- Status in working tree:
  - explicit `::INT` casting added where the merchant join uses nullable IDs
  - inputs normalized before calling validation queries

## Current Test Evidence
### Flutter
- `flutter pub get` ✅
- `flutter analyze` ✅

### Backend
- Targeted coupon regression:
  - `node --env-file=.env.test --test src/tests/coupons.validate.db.test.js src/tests/coupons.scope.test.js` ✅
- Full backend test suite:
  - `npm test` ✅ (386 tests passing)
  - `npm run verify:release:local` ✅ (`npm test` + `flow:check` both passing)
- Earlier parallel backend test execution produced spurious delivery-related failures because multiple commands were hitting the same `.env.test` database at once.
- After sequential reruns, the suite returned green and the parallel-only failures are not treated as the current baseline state.

## Current Coupon Test Result
- The targeted coupon validation regression now passes in the working tree.
- This indicates the cart-facing coupon failure is likely resolved at the backend validation layer, but broader store closure is still incomplete until the full backend suite is green.
- The current cart validation flow should continue to use the explicit backend `POST /api/coupons/validate` contract and not a generic Flutter-side fallback.

## Relevant Paths Under Review
- Backend:
  - `backend/src/modules/coupons/`
  - `backend/src/modules/orders/`
  - `backend/src/modules/owner/`
  - `backend/src/modules/admin/`
  - `backend/src/modules/commerce/`
  - `backend/src/modules/merchants/`
  - `backend/src/modules/notifications/`
  - `backend/sql/025_coupons.sql`
  - `backend/sql/061_coupon_offer_reversals.sql`
  - `backend/sql/065_drop_legacy_coupon_redemption_unique_index.sql`
- Flutter:
  - `lib/features/orders/ui/cart_screen.dart`
  - `lib/features/orders/state/cart_controller.dart`
  - `lib/features/orders/state/orders_controller.dart`
  - `lib/features/orders/data/orders_api.dart`
  - `lib/features/coupons/ui/coupon_management_screen.dart`
  - `lib/features/owner/`
  - `lib/features/admin/`

## Next Required Closure Steps
1. Inspect and fix the remaining delivery/grouped-workflow failures.
2. Continue store-specific runtime checks after the backend suite is green.
3. Keep the current coupon fix under regression coverage.
4. Update the closure report as each phase becomes verifiable.
