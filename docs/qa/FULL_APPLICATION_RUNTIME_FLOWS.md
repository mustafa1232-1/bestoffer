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

## Real Estate

- Paid-upgrade request, listing approval, workspace visibility, and business chat routing
- Seller and buyer visibility for approved listings

## Verified Runtime Evidence

- `backend/src/scripts/realEstateE2ECheck.js` now proves the real-estate workflow end-to-end:
  - super admin logs in on the user surface and approves the seller's paid-upgrade request
  - seller and buyer register and authenticate successfully with valid Basmaya addresses
  - seller submits a real-estate paid-upgrade request and receives pending / approved notifications
  - approved listing becomes visible to the buyer and to the seller workspace
  - business chat threads are created through `/api/feed/chats/threads`
  - thread messaging works for the approved listing context
  - notification targets remain stable for `real_estate_workspace` and admin pending-review routing

## Cars

- Paid-upgrade request, listing approval, workspace visibility, and business chat routing
- Seller and buyer visibility for approved listings

## Verified Runtime Evidence

- `backend/src/scripts/carsE2ECheck.js` now proves the cars workflow end-to-end:
  - super admin logs in on the user surface and approves the seller's paid-upgrade request
  - seller and buyer register and authenticate successfully with valid Basmaya addresses
  - seller submits a cars paid-upgrade request and receives pending / activated notifications
  - approved listing becomes visible to the buyer and to the seller workspace
  - business chat threads are created through `/api/feed/chats/threads`
  - thread messaging works for the approved listing context
  - notification targets remain stable for `paid_upgrades_home` and listing routing

## Pharmacy

- Pharmacy conversation, proposed cart, accept/reject/request-revision, attachment, and order conversion flows
- Customer and merchant pharmacy inboxes and deep-link routing

## Verified Runtime Evidence

- `backend/src/scripts/pharmacyE2ECheck.js` now proves the pharmacy workflow end-to-end on Railway:
  - approved merchant creation and approval remain required before pharmacy conversation access
  - customer opens a pharmacy conversation, sends messages, and uploads an attachment
  - merchant proposes a cart, revises it, and the customer accepts it
  - proposed cart conversion creates the expected order link
  - notification targets remain stable for `pharmacy_conversation`, `order_details`, and `owner_order_details`
  - attachment access URLs and conversation detail retrieval continue to work after the Pharmacy flow completes
- the runtime chain preserved the existing customer and merchant auth/session behavior while exercising Pharmacy

## Company / Admin

- Company portal login, bootstrap, dashboard, branches, users, inventory, promotions, and settings
- Admin backoffice dashboard, analytics, approval inbox, audit feed, merchant approvals, delivery approvals, taxi captain approvals, settlements, reports, permissions matrix, notifications operations, and advanced tools
- Super-admin QA access on the user surface where explicitly allowed by the auth/surface policy

## Verified Runtime Evidence

- Phase 2D now captures the runtime proof for company/admin gating and finance:
  - `backend/src/scripts/securityRuntimeCheck.js` passed on Railway for admin, accountant, and surface isolation checks
  - `backend/src/scripts/authSessionPushE2ECheck.js` passed on Railway for company/admin session bootstrap and push/realtime
  - `backend/src/scripts/financialSettlementsE2ECheck.js` passed on Railway and cleaned up its temporary merchant/user artifacts
  - company portal branch/user/inventory/promotion screens remain covered by automated UI/API tests in this phase and are not device-gated

## Finance and Settlements

- Merchant billing profile
- Merchant receivables / receivable invoices
- Merchant payment requests and allocations
- Delivery cash settlements
- Accountant summary / ledger / payroll
- Admin settlement approvals and collections

## Verified Runtime Evidence

- `backend/src/scripts/financialSettlementsE2ECheck.js` now proves the finance and settlement runtime path on Railway:
  - owner creation is bootstrapped inside the script when needed
  - admin approval and settlement flows are exercised using the live Railway backend
  - the script cleans up the temporary merchant/user artefacts it creates
- Existing repo tests still cover the underlying financial model, receivables, and payroll logic for the accountant/admin screens

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
- Voice notes, attachments, unread state, and deterministic duplicate-send handling

## Verified Runtime Evidence

- `backend/src/scripts/socialE2ECheck.js` now proves the social discovery / profile / messaging lifecycle end-to-end:
  - profiles update with the expected public-visibility fields
  - relation requests and accepts publish the expected notifications
  - search, hashtag, mentions, suggestions, share recipients, friends, profile, insights, and group chat all respond with the expected runtime shapes
- `backend/src/scripts/socialE2ECheck.js` now also proves the Phase 3B messaging hardening path end-to-end:
  - a group thread can be created for multiple recipients
  - a voice-note attachment sent with a deterministic `clientMessageId` is stored once even when retried
  - duplicate retries resolve to the same stored message id
  - unread counts remain stable for all recipients after the duplicate retry
  - community and thread chat validators accept `clientMessageId` and reject overlong values
- `backend/src/tests/feed.phase3b.test.js` now covers the new `clientMessageId` validation contract for thread and community chat bodies
- `backend/src/scripts/storiesE2ECheck.js` now proves the stories lifecycle end-to-end:
  - story creation with styled payloads works
  - story view / like / comment / highlight / archive / restore flows remain stable
  - highlight create/delete status codes stay correct
  - the story remains visible in the expected viewer list and archive surfaces
- `backend/src/scripts/reelsE2ECheck.js` now proves the reels lifecycle end-to-end:
  - reel creation with media upload works
  - reel detail, profile listing, explore, and search return the reel as expected
  - reel view / like / comment / saved toggle / share recipient discovery remain stable
- The runtime verifier now advances cleanly past the Phase 3A scripts because the social/stories/reels wrappers terminate successfully on completion.
- The runtime verifier now also advances cleanly past the Phase 3B messaging checks because the social messaging wrapper terminates successfully on completion.
