# Full Application Runtime Flows

This file captures the cross-app end-to-end flows that must be proven during the closure program.

## Auth and Session

- Login, registration, logout, logout-all, refresh, expired token, invalid token, deleted account, disabled account
- Surface and role gating for user, store, delivery, taxi captain, company/admin, and super-admin QA access

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

## Social and Messaging

- Stories autoplay/progress
- Reel sharing
- Direct messages and groups

