# Schema Overview

This is the Phase 0 schema index, not the full ERD.

## Core Domains

- Auth and sessions
- Users and roles
- Merchants and stores
- Categories and products
- Orders and order items
- Delivery and courier state
- Taxi rides, bids/offers, and tracking
- Notifications and realtime outbox
- Social feed, chat, stories, reels, and messaging
- Jobs, real estate, cars, services, pharmacy
- Company/admin and reporting

## Current Migration Baseline

- Migrations are numbered and forward-only.
- Latest visible migration at this baseline: `131_order_item_display_snapshot.sql`

## Notes

- Future database changes must add a new migration instead of editing old applied migrations.
- Phase 1 and later will expand this file with table-level ownership, foreign keys, indexes, and status fields.

