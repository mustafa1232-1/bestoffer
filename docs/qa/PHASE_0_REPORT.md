# Phase 0 Report

## Baseline

- Working branch: `closure/full-application-closure`
- Baseline commit: `a5d342e0c5957d61ae4518b2eb69538fd70b1883`
- Phase 0 documentation commit: `03dbbdd4b66aa63ee5a6155c91456498182fa764`
- Backup branch: `backup/pre-full-closure-20260711-045945`
- Phase 0 completion checkpoint commit: `187c5b231ca57e67a3ba07d5f0165dd34d27e9a9`
- Working tree at the start of this phase: clean

## Inventory Method

- Counts below use tracked files only via `git ls-files`.
- Flutter counts exclude `third_party/` vendor tests.
- Backend route counts exclude route-named tests and count route definition files only.
- Event counts are deduplicated literal event-like tags from emit / type / navigation registries.

## Exact Inventory Counts

### Flutter

| Metric | Count |
|---|---:|
| Tracked Dart files | 759 |
| Screen classes | 234 |
| Page classes | 76 |
| Dialog classes | 7 |
| Sheet / bottom sheet classes | 41 |
| Screen / page total | 310 |
| Identifiable surface classes total | 358 |
| Explicit route builder call sites | 341 |
| API client files | 30 |
| API client methods | 223 |
| Controller classes | 68 |
| State classes | 332 |
| Controller / state total | 400 |
| Flutter widget test files | 114 |

### Backend

| Metric | Count |
|---|---:|
| Route definition files | 30 |
| Registered endpoints `GET` | 333 |
| Registered endpoints `POST` | 268 |
| Registered endpoints `PUT` | 9 |
| Registered endpoints `PATCH` | 80 |
| Registered endpoints `DELETE` | 36 |
| Registered endpoints `ALL` | 0 |
| Controller files | 30 |
| Service files | 46 |
| Repository files | 45 |
| Validator files | 21 |
| Worker files | 2 |
| Script files | 31 |
| Backend test files | 63 |
| SQL migrations | 133 |

### Database Catalog

| Metric | Count |
|---|---:|
| Actual tables | 256 |
| Views | 1 |
| Materialized views | 0 |
| Primary keys | 256 |
| Foreign keys | 566 |
| Unique constraints | 86 |
| Triggers | 68 |
| Functions | 26 |
| Indexes | 847 |

Database catalog source:
- Host: `127.0.0.1`
- Database: `bestoffer_qa`

### Events

| Metric | Count |
|---|---:|
| Notification types | 44 |
| Notification target screens | 15 |
| Notification fallback screens | 6 |
| Deep-link targets | 77 |
| Realtime event tags / emit literals | 202 |

## Audit Matrix Summary

| Metric | Count |
|---|---:|
| Total rows | 19 |
| Rows for User | 3 |
| Rows for Store | 2 |
| Rows for Delivery | 1 |
| Rows for Taxi | 2 |
| Rows for Company/Admin | 1 |
| Rows for Pharmacy | 1 |
| Rows for Services | 1 |
| Rows for Jobs | 1 |
| Rows for Real Estate | 1 |
| Rows for Social | 1 |
| Rows for Messaging | 1 |
| Rows for Notifications | 1 |
| Rows for Realtime | 1 |
| Rows for Security | 1 |
| Rows for Performance | 1 |

| Status | Count |
|---|---:|
| `PASS_AUTOMATED` | 3 |
| `BLOCKED` | 14 |
| `NOT_APPLICABLE` | 2 |

## Blockers By Priority

| Priority | Count |
|---|---:|
| P0 | 8 |
| P1 | 6 |
| P2 | 3 |
| P3 | 0 |

## P0 Reproduction State

| Blocker | Status | App / role | Route / screen | Endpoint | Expected result | Actual result | Evidence / status code | Likely backend files | Likely DB tables | Required device / access | Next Phase 1 action |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Second store creation returns only `failed` | `NOT_YET_REPRODUCED` | Store / owner | store creation flow | `/api/owner/*` | Second store creation returns a structured result or a precise restriction | Not reproduced in the current Phase 0 evidence set | None yet | `backend/src/modules/owner/*`, `backend/src/modules/merchants/*` | `merchants`, `merchant_stores`, `users`, `roles` | Store app + owner account | Reproduce create/list/update/store ownership rule and capture exact backend error |
| Men/women fashion leakage | `NOT_YET_REPRODUCED` | User / customer | fashion browsing/search | `/api/merchants/*`, `/api/products/*` | Men only appears in men, women only in women, unisex in both | Not reproed in the current Phase 0 evidence set | None yet | `backend/src/modules/merchants/*`, `backend/src/modules/products/*`, `lib/features/customer/*`, `lib/features/merchants/*` | `categories`, `products`, `merchant_departments` | User app + store app | Reproduce taxonomy leakage and confirm backend query scoping |
| Missing category visibility | `NOT_YET_REPRODUCED` | Store / owner | create category | `/api/owner/*` | New category appears immediately | Not reproed in the current Phase 0 evidence set | None yet | `backend/src/modules/owner/*`, `backend/src/modules/merchants/*` | `categories`, `merchants` | Store app + owner account | Reproduce create/list/search and verify immediate visibility |
| Missing product visibility | `NOT_YET_REPRODUCED` | Store / owner | create product | `/api/owner/*` | New product appears immediately and hidden reasons are explicit | Not reproed in the current Phase 0 evidence set | None yet | `backend/src/modules/owner/*`, `backend/src/modules/products/*`, `backend/src/modules/merchants/*` | `products`, `product_variants`, `categories` | Store app + owner account | Reproduce create/list/search and verify hidden-product messaging |
| Merchant/admin coupon failure | `NOT_YET_REPRODUCED` | Merchant / admin | coupon creation/preview | `/api/coupons/*`, `/api/admin/*` | Merchant and admin coupon scopes are independently valid | Not reproed in the current Phase 0 evidence set | None yet | `backend/src/modules/coupons/*`, `lib/features/coupons/*`, `backend/src/modules/admin/*` | `coupons`, `coupon_scopes`, `coupon_usages` | Merchant/admin access + coupon creator flows | Reproduce scoped coupon creation, preview, checkout, and cancellation rollback |
| Order -> store -> delivery workflow gaps | `PARTIALLY_REPRODUCED` | User / Store / Delivery | cart, order detail, pickup | `/api/orders/*`, `/api/delivery/*` | Full order lifecycle with snapshot, notifications, and deep links | Runtime and automated coverage exists; real-device proof still missing | `PASS_AUTOMATED` / `PASS_RUNTIME` in baseline docs | `backend/src/modules/orders/*`, `backend/src/modules/delivery/*`, `backend/src/modules/notifications/*` | `orders`, `order_item`, `delivery_assignments`, `notifications` | Store/delivery app + runtime E2E + device QA | Close the last device proof gaps and confirm push/tap fidelity |
| Taxi notification / negotiation regressions | `PARTIALLY_REPRODUCED` | User / Captain | taxi negotiation | `/api/taxi/rides/*`, `/api/taxi/offers/*` | No fake active ride before assignment; offers and realtime update correctly | Runtime E2E exists, but device push/background proof remains blocked | `PASS_AUTOMATED` / `PASS_RUNTIME` in baseline docs | `backend/src/modules/taxi/*`, `backend/src/modules/notifications/*`, `lib/features/taxi/*`, `lib/core/notifications/*` | `taxi_ride`, `taxi_ride_bid`, `realtime_outbox` | User and captain apps + realtime/push access | Reproduce on device and confirm notification taps and negotiation state transitions |
| Stale-token / push-token / session regressions | `PARTIALLY_REPRODUCED` | User / Company / Taxi | auth/session/logout | `/api/auth/*`, `/api/realtime/*` | 401 vs 403 semantics stay strict and tokens do not auto-fail valid shells | Runtime checks are green; device token lifecycle still needs proof | `PASS_AUTOMATED` / `PASS_RUNTIME` in baseline docs | `backend/src/modules/auth/*`, `backend/src/modules/notifications/*`, `backend/src/shared/realtime/*`, `lib/core/network/*` | `sessions`, `tokens`, `push_tokens` | Authenticated shells + runtime checks | Reproduce token refresh/logout and confirm session invalidation behavior on device |

## Kysely Status

- Status: `NOT_INSTALLED / NOT_STARTED`
- No runtime Kysely client is installed.
- No repository has been converted.
- Numbered SQL migrations remain the only schema source of truth.

## Phase 1 Entry Scope

P0 launch blockers only:

- second store creation failure
- men / women fashion leakage
- missing category visibility
- missing product visibility
- merchant / admin coupon failure
- order -> store -> delivery workflow gaps
- taxi notification / negotiation regressions
- stale-token / push-token / session regressions

## Phase 0 Exit Note

- This report records the Phase 0 inventory baseline and blocker state only.
- Phase 1 must not start until the P0 launch blockers are the only active closure scope.
