# Social V3 Merchant Review Contract

This document records the contract that is implemented in the current Social
V3 release candidate. It intentionally does not claim order-rating or aggregate
behavior that the Social post path does not provide.

## Implemented validation

A Social merchant-review post requires:

- an authenticated user;
- `postKind=merchant_review`;
- a positive `merchantId`;
- an integer `reviewRating` from 1 through 5; and
- backend evidence that the user has at least one delivered/completed order
  belonging to that merchant.

The review caption is currently optional. The backend derives purchase
eligibility; it does not trust a client-provided verified-purchase flag.

## Persistence and sharing

The review is stored as a Social post with its merchant ID and rating. Native
Social sharing uses `merchant_review` as the shared-entity type. The backend
still authorizes the normal message destination; the client snapshot is display
metadata, not purchase-verification evidence.

## Explicit non-claims during the release freeze

The Social merchant-review post path does not currently:

- associate a specific order ID with the post;
- enforce one active Social review per user per merchant;
- write `merchant_verified_review`;
- update order-rating merchant aggregates; or
- require non-empty review text.

Those behaviors belong to the separate authoritative order-rating workflow.
Adding them to Social would require product/schema work and is outside this
dirty-deployment recovery. QA must test the implemented validation above and
must not label a Social review as an order-linked verified review.
