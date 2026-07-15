-- Reconcile the Social V3 story-interaction settings after the original
-- uncommitted 136 migration was applied to production. The migration runner
-- keys its ledger by the complete filename, so this file must be safe both on
-- a pre-feature schema and on a schema already changed by the old Social 136.

BEGIN;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS allow_likes BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_private_replies BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_comments BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_sharing BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_reshare BOOLEAN NOT NULL DEFAULT TRUE;

-- Only legacy/pre-feature rows need a backfill. Keeping the predicate is
-- important: a reconciliation run on an already-migrated database must not
-- rewrite every story (or fire its updated_at trigger), and explicit FALSE
-- values must remain unchanged.
UPDATE social_story
SET
  allow_likes = COALESCE(allow_likes, TRUE),
  allow_private_replies = COALESCE(allow_private_replies, TRUE),
  allow_comments = COALESCE(allow_comments, TRUE),
  allow_sharing = COALESCE(allow_sharing, TRUE),
  allow_reshare = COALESCE(allow_reshare, TRUE)
WHERE allow_likes IS NULL
   OR allow_private_replies IS NULL
   OR allow_comments IS NULL
   OR allow_sharing IS NULL
   OR allow_reshare IS NULL;

ALTER TABLE social_story
  ALTER COLUMN allow_likes SET DEFAULT TRUE,
  ALTER COLUMN allow_private_replies SET DEFAULT TRUE,
  ALTER COLUMN allow_comments SET DEFAULT TRUE,
  ALTER COLUMN allow_sharing SET DEFAULT TRUE,
  ALTER COLUMN allow_reshare SET DEFAULT TRUE;

ALTER TABLE social_story
  ALTER COLUMN allow_likes SET NOT NULL,
  ALTER COLUMN allow_private_replies SET NOT NULL,
  ALTER COLUMN allow_comments SET NOT NULL,
  ALTER COLUMN allow_sharing SET NOT NULL,
  ALTER COLUMN allow_reshare SET NOT NULL;

-- The dirty Social tree also introduced native Story/Profile/User/Merchant
-- Review chat cards. Older migrations constrain the two persisted chat tables
-- to an earlier allowlist, so merely updating request validation would still
-- fail at INSERT time. Reconcile each named constraint only when its current
-- definition does not contain the complete canonical allowlist. This avoids
-- dropping/revalidating an already-correct production constraint on every
-- startup.
DO $migration$
DECLARE
  constraint_definition TEXT;
  constraint_is_current BOOLEAN := FALSE;
BEGIN
  IF to_regclass('social_chat_message') IS NOT NULL THEN
    SELECT pg_get_constraintdef(c.oid)
      INTO constraint_definition
      FROM pg_constraint c
     WHERE c.conrelid = 'social_chat_message'::regclass
       AND c.conname = 'social_chat_message_shared_entity_type_chk';

    IF constraint_definition IS NOT NULL THEN
      SELECT BOOL_AND(STRPOS(constraint_definition, QUOTE_LITERAL(allowed_type)) > 0)
        INTO constraint_is_current
        FROM UNNEST(ARRAY[
          'post', 'reel', 'story', 'profile', 'user', 'review',
          'merchant_review', 'car_listing', 'real_estate_listing', 'location',
          'service_offering', 'service_provider', 'service_request'
        ]::TEXT[]) AS allowed(allowed_type);
    END IF;

    IF NOT COALESCE(constraint_is_current, FALSE) THEN
      ALTER TABLE social_chat_message
        DROP CONSTRAINT IF EXISTS social_chat_message_shared_entity_type_chk;
      ALTER TABLE social_chat_message
        ADD CONSTRAINT social_chat_message_shared_entity_type_chk
        CHECK (
          shared_entity_type IS NULL
          OR shared_entity_type IN (
            'post', 'reel', 'story', 'profile', 'user', 'review',
            'merchant_review', 'car_listing', 'real_estate_listing', 'location',
            'service_offering', 'service_provider', 'service_request'
          )
        );
    END IF;
  END IF;
END
$migration$;

DO $migration$
DECLARE
  constraint_definition TEXT;
  constraint_is_current BOOLEAN := FALSE;
BEGIN
  IF to_regclass('social_scope_chat_message') IS NOT NULL THEN
    SELECT pg_get_constraintdef(c.oid)
      INTO constraint_definition
      FROM pg_constraint c
     WHERE c.conrelid = 'social_scope_chat_message'::regclass
       AND c.conname = 'social_scope_chat_message_shared_entity_type_chk';

    IF constraint_definition IS NOT NULL THEN
      SELECT BOOL_AND(STRPOS(constraint_definition, QUOTE_LITERAL(allowed_type)) > 0)
        INTO constraint_is_current
        FROM UNNEST(ARRAY[
          'post', 'reel', 'story', 'profile', 'user', 'review',
          'merchant_review', 'car_listing', 'real_estate_listing', 'location',
          'service_offering', 'service_provider', 'service_request'
        ]::TEXT[]) AS allowed(allowed_type);
    END IF;

    IF NOT COALESCE(constraint_is_current, FALSE) THEN
      ALTER TABLE social_scope_chat_message
        DROP CONSTRAINT IF EXISTS social_scope_chat_message_shared_entity_type_chk;
      ALTER TABLE social_scope_chat_message
        ADD CONSTRAINT social_scope_chat_message_shared_entity_type_chk
        CHECK (
          shared_entity_type IS NULL
          OR shared_entity_type IN (
            'post', 'reel', 'story', 'profile', 'user', 'review',
            'merchant_review', 'car_listing', 'real_estate_listing', 'location',
            'service_offering', 'service_provider', 'service_request'
          )
        );
    END IF;
  END IF;
END
$migration$;

COMMIT;
