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
- Company portal, backoffice admin, merchant billing, receivables, settlements, approvals, audit logs, and operational control
- Social feed, chat, stories, reels, and messaging
- Jobs, real estate, cars, services, pharmacy
- Company/admin and reporting

## Current Migration Baseline

- Migrations are numbered and forward-only.
- Confirmed company and finance baseline tables include `company`, `company_user`, `company_default_policy`, `company_branch_request`, `company_audit_log`, `merchant_billing_profile`, `merchant_receivables_ledger`, `merchant_payment_request`, `merchant_receivable_invoice`, `merchant_settlement`, `delivery_cash_settlement`, `merchant_cash_ledger_entry`, and `admin_audit_event`.
- Pharmacy workflow tables were introduced by `088_store_activity_and_pharmacy_workflow.sql` and are exercised by the phase 2C runtime proof.
- Latest visible migration at this baseline: `132_social_chat_client_message_id.sql`
- `131_order_item_display_snapshot.sql` remains the preceding order-item snapshot baseline.
- `132_social_chat_client_message_id.sql` adds stable social chat client-message IDs and uniqueness protection for direct and scoped chat retries.

## Notes

- Future database changes must add a new migration instead of editing old applied migrations.
- Phase 1 and later will expand this file with table-level ownership, foreign keys, indexes, and status fields.
