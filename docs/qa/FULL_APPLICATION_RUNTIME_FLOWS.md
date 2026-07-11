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

## Taxi

- Request ride
- Receive offers
- Accept/counter/reject
- Atomic assignment
- Chat gating
- Live tracking gating

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
