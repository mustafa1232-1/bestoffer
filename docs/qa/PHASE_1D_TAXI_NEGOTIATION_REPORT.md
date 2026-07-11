# Phase 1D Report - Taxi Negotiation and Lifecycle

## Scope

Phase 1D covers the P0 taxi negotiation and lifecycle slice only:

- user ride request creation
- multiple captain offers
- customer counter-offer / accept / reject
- captain direct customer-fare acceptance
- atomic assignment and losing-captain rejection
- chat gating
- live tracking gating
- arrive / start / complete lifecycle transitions

No Store, Orders, Delivery, Social, or unrelated business logic was changed in this phase.

## Outcome

- Local taxi runtime verification passed.
- Railway runtime verification passed.
- Flutter analysis and Flutter tests remained green after the taxi changes.
- Backend unit tests remained green after the taxi changes.
- Real-device taxi push/background/killed-app validation remains pending.

## Deployment Confirmation

- Local HEAD at deployment time: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Pushed branch HEAD at deployment time: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Railway service: `bestoffer`
- Railway environment: `production`
- Railway deployment id: `499746db-3ec6-426c-921d-4f7024c87956`
- Deployment status: `SUCCESS`
- `/health`: `200`
- `/ready`: `200`
- Deployed commit: `4034661545ea66366a6bc741b3327d13b4767b0d`

## What Was Proven

- A ride can be created with valid pickup, destination, fare, and note data.
- Multiple approved captains can receive the same request and participate in negotiation.
- The direct captain acceptance flow now assigns a ride atomically.
- Racing captain acceptance returns a controlled `409` for the loser.
- The assigned captain can continue the lifecycle through `arrive`, `start`, and `complete`.
- Customer and captain current-ride views clear after terminal completion.
- Negotiation flow still supports bids, counter-offers, acceptance, chat, and live tracking gates.
- A losing captain cannot continue a ride after assignment.

## Verification

- `node --env-file=.env.test src/scripts/taxiE2ECheck.js`
- `railway run --service bestoffer npm run verify:release:runtime`
- `flutter analyze`
- `flutter test`
- `cd backend && npm test`
- `cd backend && npm run verify:release:local`

## Runtime Evidence

- `backend/src/scripts/taxiE2ECheck.js`
- `backend/src/scripts/verifyReleaseRuntime.js`

## Notes

- The earlier E2E failure was caused by a stale lifecycle expectation in the taxi script, which attempted to complete a ride before it had moved through `arrive` and `start`.
- The phase is runtime-proven, but device QA for taxi push/background/killed-app flows is still blocked until a controllable device session is available.
- This phase keeps the existing bid storage model and app-facing offer terminology.
