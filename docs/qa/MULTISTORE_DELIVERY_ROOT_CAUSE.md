# Multi-store delivery assignment — root cause

Branch `fix/delivery-multistore-store-release-closure`, base `7a73125` (contains
Codex's completed Social V3). Evidence gathered against the reachable local
PostgreSQL test DB; reproduced deterministically via a fixture (no production
order needed).

## Symptom
A multi-store checkout shows "Courier assigned" on the Store/User surface while
the assigned Courier's app receives no coherent job.

## Authoritative root cause (proven, not inferred)
1. **No grouped delivery entity existed.** Assignment was per child
   `customer_order` (`courier_assignment.order_id`, `customer_order.delivery_user_id`).
   `order_group` grouped the *checkout* (`is_multi_store`, `stores_count`) but
   there was **no delivery job** binding one courier to the group's N child
   orders + N pickup stops.
2. **A legacy partial unique index made grouped assignment impossible.**
   ```
   uq_customer_order_assigned_driver_active
     = UNIQUE (delivery_user_id)
       WHERE delivery_assignment_status = 'ASSIGNED' AND delivery_user_id IS NOT NULL
   ```
   This enforced **one active assigned order per driver**. Assigning one courier
   to the 2nd child order of a multi-store group throws
   `duplicate key value violates unique constraint "uq_customer_order_assigned_driver_active"`
   — captured live in the step-by-step diagnostic. So the assignment either
   partially applied (one child assigned, others not) or failed, leaving the
   group's UI/aggregate reading "assigned" from a per-child flag while the
   courier's `WHERE delivery_user_id = $1` query returned an incomplete/empty
   grouped view.

### Why the UI showed assigned but the courier didn't receive it
Store/User "assigned" was derived from a per-child `delivery_assignment_status`
flag, not from an authoritative grouped assignment. The courier query keyed on a
single child's `delivery_user_id`. With the unique-index conflict blocking a
consistent multi-child assignment, the two sides disagreed.

## Fix implemented (this branch)
- **Migration `136_delivery_grouped_job.sql`** (applied + idempotent-verified on
  the local DB):
  - `delivery_job` (one per `order_group`, unique `order_group_id`), status
    machine, idempotency key, version, courier + dropoff snapshot.
  - `delivery_pickup_stop` (one per child order, unique `child_order_id`).
  - `notification_outbox` (transactional outbox — none existed before).
  - **Root-cause constraint fix:** `uq_customer_order_assigned_driver_active` is
    now scoped to **single (non-group) orders** (`... AND order_group_id IS NULL`),
    and the "one active delivery per driver" invariant is enforced authoritatively
    on `delivery_job` (`uq_delivery_job_assigned_courier_active`).
- **`delivery-job.service.js`**: `ensureDeliveryJobForGroup`,
  `recomputeGroupReadiness`, `selectEligibleCourier` (explicit exclusion reasons),
  `assignDeliveryJobTx` (row-locked, idempotent, writes the outbox event in the
  same transaction, never ASSIGNED without a courier + active pickups),
  `listCourierGroupedJobs` (authoritative grouped courier query),
  `getGroupedAssignmentView` (false-assigned prevention).

## Evidence (DB-backed regression tests — all PASS)
`src/tests/delivery.grouped-assignment.test.js` (fixture:
`src/tests/fixtures/multistore-delivery.fixture.js`):
1. DEFECT reproduction — legacy per-child "assigned" flag set, grouped view
   `active:false`, courier grouped query empty.
2. FIX — one `delivery_job`, one courier, two pickup stops; courier sees ONE
   grouped job with `numberOfStores=2`; User view `active:true`; outbox event
   `COURIER_MULTI_STORE_DELIVERY_ASSIGNED` created in the same transaction; both
   child orders mirror the same courier.
3. Concurrency — two simultaneous assignment transactions → exactly one fresh
   assignment (row lock + conditional update), still one grouped job.
4. `PENDING_NO_DRIVER` — no eligible courier → not assigned, no false state,
   exclusion reason recorded.
5. Partial cancellation — a cancelled child is removed from active pickups; the
   group stays assignable with the remaining store.

Existing delivery suite (21 tests) still passes → the single-order flow is not
regressed by the index change.

## Not yet done in this pass (honest)
Flutter Courier grouped-job models/screens, Store/User assignment-view wiring,
the outbox *worker* + FCM send, session refresh, and the full Store release audit
are separate large layers. Device/iOS/signed-release/Railway verification are
externally BLOCKED. See the closure report.
