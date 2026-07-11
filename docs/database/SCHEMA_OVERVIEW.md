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
- Pharmacy conversations, proposed carts, attachments, messages, and retention tracking
- Social feed, chat, stories, reels, and messaging
- Jobs, real estate, cars, services, pharmacy
- Company/admin and reporting

## Current Migration Baseline

- Migrations are numbered and forward-only.
- Pharmacy workflow tables were introduced by `088_store_activity_and_pharmacy_workflow.sql` and are exercised by the phase 2C runtime proof.
- Latest visible migration at this baseline: `131_order_item_display_snapshot.sql`

## Notes

- Future database changes must add a new migration instead of editing old applied migrations.
- Phase 1 and later will expand this file with table-level ownership, foreign keys, indexes, and status fields.
