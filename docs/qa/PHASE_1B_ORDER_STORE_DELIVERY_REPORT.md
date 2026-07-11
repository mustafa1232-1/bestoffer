# Phase 1B Report - Order / Store / Delivery

## Scope

Phase 1B covers the P0 order -> store -> delivery runtime slice only:

- customer order creation
- store approval
- store start-preparing
- courier assignment
- courier accept / picked-up / arrived / delivered
- customer confirmation
- notification coverage on the order lifecycle

No Taxi, Kysely, social, or unrelated business logic was changed in this phase.

## Runtime Proof

### Local QA

- `node --env-file=.env.test src/scripts/orderE2ECheck.js`
  - passed
- `npm run verify:release:local`
  - passed

### Railway Runtime

- `railway run --service bestoffer npm run verify:release:runtime`
  - passed

## Observed Flow

The runtime script proved the complete order lifecycle:

- customer registers and creates the order
- owner approves the merchant and accepts financial terms
- owner creates category, product, coupon, and offer data
- owner validates the coupon before order creation
- customer creates a discounted order
- owner cancels the first order and coupon / offer usage is restored
- customer creates the replacement order
- owner moves the order to preparing
- owner assigns the delivery agent
- courier logs in and accepts the order
- owner marks the order ready for pickup
- courier picks up the order
- courier marks the order arrived
- courier marks the order delivered
- customer confirms receipt

## Notification Evidence

The runtime pass observed the expected order notifications:

- `order_courier_assigned`
- `owner_customer_received`

## Root Cause Note

The first direct attempt to run `npm run e2e:order:check` failed because the root `.env` points to the Railway database URL, while the local QA database for this phase is `127.0.0.1:55432`. The correct local invocation is:

```powershell
node --env-file=.env.test src/scripts/orderE2ECheck.js
```

That was an environment selection issue, not a business-logic regression.

## Verification Result

- Order workflow runtime proof: `PASS_RUNTIME`
- Device proof: `BLOCKED: REAL_DEVICE_REQUIRED`
- Final status: `PASS_RUNTIME`

