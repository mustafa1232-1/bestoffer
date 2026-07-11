# Full Application Runtime Flows

This file captures the cross-app end-to-end flows that must be proven during the closure program.

## Auth and Session

- Login, registration, logout, logout-all, refresh, expired token, invalid token, deleted account, disabled account
- Surface and role gating for user, store, delivery, taxi captain, company/admin, and super-admin QA access
- Phase 1C runtime proof now covers the full auth/session/push lifecycle:
  - guest `NO_TOKEN` failures on `/api/realtime/token` and `/api/notifications/push-token` do not trigger terminal session invalidation
  - super admin login on the user surface returns a valid authenticated shell with `isSuperAdmin=true`
  - super admin is blocked on a non-permitted surface during login
  - owner, customer, delivery, and captain shells all survive login, refresh, logout-all, push-token registration, and realtime-token issuance
  - stale session, token, and push state is cleared without breaking the next authenticated session

## Store / Catalog / Fashion

- Create store
- Create category
- Create product
- Department separation for men / women / unisex
- Search and list visibility
- Hidden product explanation

## Commerce

- Add to cart
- Variant selection
- Checkout preview
- Order creation
- Store approval
- Delivery assignment
- Receipt/invoice

## Verified Runtime Evidence

- `backend/src/scripts/orderE2ECheck.js` now proves the end-to-end order path:
  - customer registers and creates an order
  - owner approves the merchant and accepts financial terms
  - owner starts preparing the order
  - owner assigns a courier
  - courier accepts, picks up, arrives, delivers, and the customer confirms receipt
- Runtime assertions observed the expected notifications:
  - `order_courier_assigned`
  - `owner_customer_received`
- The same runtime pass verified that:
  - cancelled orders restore coupon and offer usage state
  - the replacement order keeps the expected discounted pricing
  - owner and courier current-order views hide completed orders after final confirmation

## Services

- Provider onboarding
- Offering approval and public discovery
- Customer request / provider quote / customer accept
- Completion and notification routing

## Verified Runtime Evidence

- `backend/src/scripts/servicesE2ECheck.js` now proves the services lifecycle end-to-end:
  - admin seeds or reuses a valid service category pair
  - provider subscription onboarding completes
  - provider workspace loads after approval
  - provider creates an offering that becomes visible after admin approval
  - customer creates a request, provider lists it, creates a quote, customer accepts it, and the provider advances it to completion
  - customer notifications stay on the service request details target
  - provider and admin notification contracts remain intact

## Jobs

- Create job
- Duplicate apply blocking
- Hire, accept offer, withdraw
- Expired-job rejection

## Verified Runtime Evidence

- `backend/src/scripts/jobsE2ECheck.js` now proves the jobs workflow end-to-end:
  - owner and HR can create/manage jobs
  - duplicate job applications are blocked with `409`
  - hired candidates can accept the offer and persist the work profile
  - withdraw works before acceptance and is blocked after acceptance
  - expired jobs reject new applications
  - manager notifications include the job offer accepted / withdrawn flows

## Taxi

- Request ride
- Receive offers
- Accept/counter/reject
- Atomic assignment
- Chat gating
- Live tracking gating

## Verified Runtime Evidence

- `backend/src/scripts/taxiE2ECheck.js` now proves the taxi lifecycle end-to-end:
  - customer creates a ride request with valid pickup, destination, fare, and note fields
  - multiple approved captains can enter the negotiation flow
  - direct captain acceptance assigns the ride atomically
  - racing captain acceptance returns a controlled `409`
  - the assigned captain can advance the ride through arrive, start, and complete transitions
  - customer and captain current-ride views clear after completion
  - multi-offer negotiation still works with bids, counter-offers, acceptance, chat, and live tracking gates
  - a losing captain cannot continue the ride after assignment
- Runtime assertions observed the expected taxi notifications and state transitions in the Railway-backed verification chain.

## Notifications / Realtime

- Foreground, background, and killed-app notification handling
- Tap routing to exact target screen
- Realtime reconnection and deduplication
- Phase 1C runtime proof also verified:
  - push token registration/unregistration works after login
  - realtime token issuance is skipped for guests and resumes after successful auth
  - logout-all revokes the second live session cleanly
  - the Railway runtime chain now passes the auth/session/push stage before the later E2E suites

## Social and Messaging

- Stories autoplay/progress
- Reel sharing
- Direct messages and groups
