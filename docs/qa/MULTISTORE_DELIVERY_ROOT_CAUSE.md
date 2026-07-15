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

## Production integration (second pass — the isolation is now closed)
The grouped service is no longer isolated from production. It is wired into the
real order lifecycle:

- **Checkout (§2)** — `createOrderGroupWithItems` now calls
  `ensureDeliveryJobForGroup` inside the checkout transaction, so every
  multi-store group gets its `delivery_job` + one `delivery_pickup_stop` per
  child atomically (job starts `PENDING_STORES`, no premature courier).
- **Store acceptance/cancellation (§3)** — `updateOwnerOrderStatus` now, for a
  group child, re-syncs the pickup stop and `recomputeGroupReadiness` inside the
  same transaction. Readiness flips to `READY_FOR_ASSIGNMENT` only when every
  active child is accepted (note: the real owner flow uses `approved`, so that
  status is part of the accepted set); it flips to `CANCELLED` when the last
  active child is cancelled.
- **Assignment worker cutover (§4)** — `loadPendingAssignmentOrders` now excludes
  `order_scope = 'group_child'`, so the per-child worker can never partially
  assign a group. A new `processGroupedAssignmentBatch` pass loads assignable
  `delivery_job`s (`FOR UPDATE SKIP LOCKED`), assigns one courier per job via the
  authoritative transaction (conflict-retry to the next eligible courier), and is
  invoked from the existing recovery batch + startup worker.
- **Notification outbox worker (§11)** — `notification-outbox.worker.js` drains
  `notification_outbox` rows through the existing notification infrastructure
  with `FOR UPDATE SKIP LOCKED`, `eventId` idempotency, bounded exponential
  backoff, and `DEAD_LETTER`. Registered in `server.js`
  (`startNotificationOutboxWorker`).

### Proof — real end-to-end test (§16)
`src/tests/delivery.grouped-e2e.test.js` drives the REAL path (it never calls
`assignDeliveryJobTx` directly): a real two-store checkout via
`createOrderGroupWithItems` → real `updateOwnerOrderStatus` acceptance for both
stores → the real `processGroupedAssignmentBatch` worker. It asserts one job, one
courier, two stops, both children mirroring the courier, the courier grouped
query returning one job (`numberOfStores=2`), the User view active, the outbox
event present, and that the per-order worker excludes the group children.

Full backend suite: **324/324 passing** (was 324 before + this work; existing
single-order delivery flow unaffected).

## Third pass — notification truth + authoritative assignment + courier APIs
Migration **137** (additive on top of 136, which is untouched) plus code:

- **Truthful outbox delivery (§1)** — `notification_outbox` now has a real state
  machine (`CREATED → PROCESSING → NOTIFICATION_CREATED → PUSH_ACCEPTED /
  PUSH_PARTIAL / PUSH_RETRY / PUSH_FAILED → DEAD_LETTER`) with
  `app_notification_id`, `processing_started_at`, `lease_expires_at` (crash
  recovery), `completed_at`, `provider_result_json`. Creating an app_notification
  is no longer mistaken for provider acceptance; Firebase-not-configured and
  no-tokens are never `PUSH_ACCEPTED`.
- **Idempotent notifications (§2)** — `app_notification.event_id` + partial
  unique index; `createNotificationAndAwaitDelivery` inserts one row per event
  (`ON CONFLICT (event_id) DO NOTHING`). A crash after creation but before outbox
  completion recovers via the lease and does **not** duplicate the notification
  (regression-tested).
- **Awaited push API (§3)** — `dispatchNotificationWithResult` returns a
  structured `{firebaseConfigured, totalTokens, acceptedTokens, deadTokens,
  retryableFailures, permanentFailures, providerMessageIds}`; the outbox worker
  derives the truthful state from it. `queuePushNotification` (fire-and-forget)
  is unchanged for existing callers.
- **Urgent channel contract (§4)** — allow-listed
  `maslaki_courier_assignments_urgent_v2` / `maslaki_store_orders_urgent_v2`
  honored from the event contract (arbitrary client channel IDs ignored); FCM
  data carries `eventId/eventType/schemaVersion/deliveryJobId/orderGroupId/
  assignmentId/numberOfStores/route/requiresAction`; urgent events do not
  collapse.
- **Surface enforcement (§5)** — authoritative surface is `delivery` (migration
  137 normalizes the old `courier` rows); the worker fails closed on a
  role/target-surface mismatch and records a safe diagnostic. Only tokens of the
  matching surface receive the event.
- **Authoritative grouped `courier_assignment` (§6)** — `order_id` is now
  nullable; `delivery_job_id` added with `CHECK (num_nonnulls(order_id,
  delivery_job_id)=1)` and a partial unique index (one active grouped assignment
  per job). `assignDeliveryJobTx` creates exactly ONE grouped row in the same
  transaction and returns `assignmentId`; migration backfills jobs assigned
  before 137. Views/payloads expose `assignmentId`.
- **Complete eligibility (§7)** — `selectEligibleCourier` verifies role,
  `delivery_account_approved`, not-disabled, not-locked, app-courier, active,
  online, fresh presence, not busy in a grouped job, and not busy in the legacy
  per-order flow — each with a precise exclusion reason (DB-tested).
- **Courier grouped-job APIs (§8)** — registered on `deliveryRouter`
  (`requireDeliveryAgent`): list/current/details + `acknowledge`,
  `heading-to-pickups`, `stops/:id/arrived`, `stops/:id/collected`,
  `heading-to-customer`, `delivered`. Server enforces transition order
  (cannot head to customer before all active stops collected; cannot deliver
  before heading; duplicates idempotent; stale `version` rejected; ownership
  validated).
- **Normalized assignment view (§9)** — `getGroupedAssignmentView` returns
  `{id, assignmentId, deliveryJobId, orderGroupId, courierUserId/Name/Phone/Photo,
  active, assignmentStatus, lifecycleStatus, numberOfStores, pickupProgress}` and
  is active only when the authoritative assignment is complete.

### Tests
Full backend suite **326/326 passing**, including: outbox truthful-delivery (8
provider scenarios incl. crash-window idempotency + surface suppression),
eligibility exclusions, grouped `courier_assignment`, and an extended real
end-to-end (checkout → acceptance → worker assignment → grouped assignment →
outbox→one app_notification→no-duplicate → surface suppression → acknowledge →
per-stop collect (stop 1 collected, stop 2 pending) → head-to-customer gating →
delivered on all surfaces). The final acceptance never calls `assignDeliveryJobTx`
directly.

## Fourth pass — Social integration + four verified backend defects
- **Social baseline integrated** — merged `feat/social-v3-interactions-reviews-closure`
  (`ca6a5c0`) into this branch (merge `210328a`). Disjoint file sets except
  `package.json` (clean). Source migration order preserved:
  `136_delivery_grouped_job` → `137_delivery_grouped_notification_truth` →
  `140_social_story_interaction_settings`. Full suite green afterward.
- **Defect A (§2)** — `getCourierCurrentGroupedJob` now returns only an active,
  non-terminal job (never DELIVERED/CANCELLED/FAILED) or null;
  `listCourierGroupedJobs` excludes terminal lifecycle states; added
  `listCourierActiveGroupedJobs` + `listCourierGroupedJobHistory` and a
  `/delivery-jobs/history` route. App-restart after delivery does not reopen work.
- **Defect B (§3)** — `selectEligibleCourier` accepts `excludeCourierUserIds`;
  the conflict-retry loop excludes each collided candidate and uses a SAVEPOINT so
  a failed attempt rolls back cleanly, then assigns the NEXT eligible courier —
  `PENDING_NO_DRIVER` only when no candidate remains (DB-tested: A collides → B
  wins, one active assignment).
- **Defect C (§4)** — the grouped `courier_assignment` insert no longer silently
  replaces the courier: same courier is idempotent, a different courier throws
  `ASSIGNMENT_CONFLICT`. Added an explicit audited `reassignGroupedJob`
  transaction (lock job + active assignment → close old with reason → assign new →
  fresh per-courier outbox event). Outbox `event_id` is now per-courier so a
  reassignment notifies the new courier.
- **Defect D (§5)** — normalized `assignment.active` derives from IDENTITY
  (assignmentId + deliveryJobId + courierUserId + ASSIGNED + non-ended assignment
  + non-terminal lifecycle), never from `courier_name`; name/photo/phone are
  presentation with safe fallbacks. The view now returns the full `pickupStops`
  array (store identity, address, coords, sequence, statuses).

Tests: full backend suite **340/340 pass**. New `delivery.defects.test.js` covers
all four defects incl. reassignment and the retry-to-next-courier path.

## Not yet done (honest — next layers)
- **§10/§11 Flutter Delivery + Store/User apps** — grouped-job models, API
  client, controllers, screens, lifecycle controls, cache invalidation. Not
  started; no Flutter source changed.
- **§12 Android urgent channel implementation** in the Flutter/Android targets
  (channel creation, sound/vibration, POST_NOTIFICATIONS, getInitialMessage /
  onMessageOpenedApp, foreground/background/terminated handling). The backend
  emits the correct channel + payload contract; the client side is not built.
- **§13 presence cadence + session persistence audit** and
  `docs/qa/STORE_APP_FULL_RELEASE_AUDIT.md` — not done.
- **§15 QA APKs** — not built (no Flutter changes this pass).
- Device / iOS / signed-release / Railway verification remain externally BLOCKED.

Per the atomic-cutover rule, migrations 136+137 must not be merged to
`closure/full-application-closure` or applied to Railway until the Flutter/client
layers land.
