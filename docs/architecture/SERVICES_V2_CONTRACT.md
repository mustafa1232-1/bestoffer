# Services V2 Contract

Status: decision-complete design boundary for Services V2. This file defines the implementation contract before backend, Flutter, or SQL mutation.

## Baseline

- Base SHA: `7eb2da1dbfdc33ddd4616e7289f6e11586023056`
- Current branch: `feat/services-booking-v2-production-closure`
- Backup branch: `backup/pre-services-v2-production-closure`
- Service-related preexisting files: `25`
- Unrelated preexisting files: `120`
- Baseline documents: `3`
- Highest migration currently present in the working tree: `154`
- Highest migration file: `backend/sql/154_taxi_price_raise_round.sql`
- Migration `154` is currently untracked and is not reserved for Services V2 by this contract.

## Scope Boundaries

### BASE_COMMITTED_CODE

- Code already committed at the base SHA.
- Treat baseline docs and current repository state as the only source of truth.

### PREEXISTING_UNCOMMITTED_SERVICE_WORK

- The 25 service-related files listed in `docs/qa/SERVICES_V2_PREEXISTING_CHANGES.md`.
- These files may be edited, but earlier edits must remain preserved and each file change must be documented as additive V2 work.
- Required per-file recording categories:
  - `preexisting changes preserved`
  - `Services V2 additions`
  - `conflicts resolved`
  - `tests added`

### PROPOSED_V2_CONTRACT

- The direct-booking and pricing contract that future code must satisfy.
- This document is the design boundary only; it does not by itself authorize code changes.

## Required Pricing and Booking Types

### Pricing types

- `FIXED`
- `HOURLY`
- `PER_VISIT`
- `PER_UNIT`
- `INSPECTION_REQUIRED`

### Booking state machine

- `PENDING_PROVIDER_CONFIRMATION`
- `CONFIRMED`
- `IN_PROGRESS`
- `PROVIDER_COMPLETED`
- `COMPLETED`
- `REJECTED_BY_PROVIDER`
- `CANCELLED_BY_CUSTOMER`
- `CANCELLED_BY_PROVIDER`
- `CANCELLED_BY_ADMIN`
- `EXPIRED`
- `DISPUTED`

### Booking flow kind

- `LEGACY`
- `V2`
- `booking_flow_kind` is the authoritative flow discriminator.
- `booking_flow_kind` is immutable after create.
- Legacy quote/request bookings must persist `booking_flow_kind = 'LEGACY'`.
- Direct-booking V2 requests must persist `booking_flow_kind = 'V2'`.
- `booking_version` is the optimistic state version for the booking row and is not a flow discriminator.
- `booking_version` starts at `1` for legacy bookings and `2` for V2 bookings, then increments on each successful booking mutation.
- `isDirectBookingV2(request)` is defined as `request.booking_flow_kind === 'V2'`.
- Null flow kinds are only tolerated for pre-migration compatibility; the migration and application code must prevent new nulls.

## Booking Invariants

- `assertValidServiceBookingTransition(expectedVersion, idempotencyKey)` is required for every state-changing booking action.
- Booking transitions must be versioned and idempotent.
- Replay with the same idempotency key must not duplicate the booking, transition, promotion snapshot, or notification record.
- Any state transition that changes price or booking state must occur inside a transaction.
- `HTTP 409 SERVICE_PRICE_CHANGED` is the expected failure when the client's expected price version is stale.

## Pricing Contract

- Canonical pricing fixture:
  - `5000 IQD/hour`
  - `10:00-14:00`
  - `240 minutes`
  - `4 hours`
  - `subtotal = 20000 IQD`
- Preview must return:
  - `priceVersion`
  - `unitPriceIqd`
  - `quantity`
  - `durationMinutes`
  - `subtotalIqd`
  - `discountIqd`
  - `serviceFeeIqd`
  - `totalIqd`
  - `promotionSnapshot`
  - `expiresAt`
- Create must recompute price inside the transaction.
- Promotions must support:
  - `PERCENTAGE`
  - `FIXED_AMOUNT`
  - `SPECIAL_UNIT_PRICE`
- Only one active promotion may apply per service at a time.
- Promotion snapshots are immutable once attached to a booking.
- The canonical 4-hour fixture must stay stable across the pricing engine, preview, create, DB snapshot, and Flutter invoice surfaces.

## Booking Lifecycle Contract

- `create` establishes the booking in a transactional, versioned, idempotent manner.
- Provider confirmation must be locked against duplicate confirmation races.
- The source of truth for terminal completion is explicit:
  - provider finishes to `PROVIDER_COMPLETED`
  - user confirms `COMPLETED` or opens `DISPUTED`
  - an idempotent 24-hour worker finalizes exactly once
- Booking completion must not delete V1 tables, quote tables, or production history.

## Notifications and Recovery

- Notification delivery must use a durable outbox with:
  - unique `event_key`
  - retry metadata
  - `next_attempt_at`
  - `sent/failed/dead-letter`
  - `target_app`
  - `deep_link`
- Recovery and completion workers must be idempotent and transaction-safe.
- Notification sending must not be the transaction source of truth.

## Flutter Guardrails

- `service_provider` users must enter only through `ServiceProviderShell`.
- Real role guards and real deep-link guards are required for provider-only surfaces.
- Preview/create/invoice screens must render the same pricing snapshot and payment math from the backend.
- Existing legacy screens may remain only when still functional; broken flow edges should be replaced rather than layered over.

## Phase 1 Constraints

- No destructive production cleanup.
- No deletion of V1 tables.
- No deletion of quote tables.
- No loss of preexisting service work.
- No untracked side effects outside the Services V2 scope.

## Implementation Notes

- The backend may extend existing `service_requests` / pricing / promotion structures rather than inventing a parallel model, provided the published contract above is satisfied.
- The 25 dirty service files are not forbidden from modification; they are protected from accidental overwrite and must be reviewed change-by-change.
- Any mismatch between the contract and the current repository state must be resolved before feature completion.

## References

- `docs/qa/SERVICES_V2_BASELINE.md`
- `docs/qa/SERVICES_V2_PREEXISTING_CHANGES.md`
- `docs/qa/SERVICES_V2_PREEXISTING_DIFF_SUMMARY.txt`
