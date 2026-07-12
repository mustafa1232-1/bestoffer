# Migration Audit

Phase 3C integrity check for numbered SQL migrations.

## Scope

- Verify migration `132_social_chat_client_message_id.sql` exists in the repo.
- Verify migration 132 is applied in local QA and Railway.
- Confirm no destructive edit to an already applied migration.

## Findings

| Migration | Status | Evidence | Notes |
|---|---|---|---|
| `131_order_item_display_snapshot.sql` | PASS | Baseline order snapshot migration already exists in the repo and was not recreated during Phase 3C. | Remains the preceding order-item display baseline. |
| `132_social_chat_client_message_id.sql` | PASS | Present in `backend/sql/132_social_chat_client_message_id.sql`; local QA DB and Railway both show it as the latest visible migration entry. | Adds idempotent social chat client-message IDs and unique partial indexes. |

## Migration 132 Content

- Adds `client_message_id` to `social_chat_message`.
- Adds `client_message_id` to `social_scope_chat_message`.
- Creates `social_chat_message_client_message_id_unique`.
- Creates `social_scope_chat_message_client_message_id_unique`.

## Database Application Check

- Local QA DB (`.env.test`)
  - `schema_migration` rows: `134`
  - latest visible migration: `132_social_chat_client_message_id.sql`
  - both unique indexes are present
- Railway DB
  - `schema_migration` rows: `136`
  - latest visible migration: `132_social_chat_client_message_id.sql`
  - both unique indexes are present

## Conclusion

- Migration 132 is intact.
- No applied migration was edited in place.
- No backfill or destructive schema rewrite was required for Phase 3C.
