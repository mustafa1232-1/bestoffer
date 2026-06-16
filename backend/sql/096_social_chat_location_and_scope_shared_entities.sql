BEGIN;

ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_shared_entity_type_chk;

ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN (
      'post',
      'reel',
      'review',
      'car_listing',
      'real_estate_listing',
      'location'
    )
  );

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS shared_entity_type VARCHAR(32);

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS shared_entity_id BIGINT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS shared_snapshot_json JSONB;

ALTER TABLE social_scope_chat_message
  DROP CONSTRAINT IF EXISTS social_scope_chat_message_shared_entity_type_chk;

ALTER TABLE social_scope_chat_message
  ADD CONSTRAINT social_scope_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN (
      'post',
      'reel',
      'review',
      'car_listing',
      'real_estate_listing',
      'location'
    )
  );

ALTER TABLE social_scope_chat_message
  DROP CONSTRAINT IF EXISTS social_scope_chat_message_shared_entity_pair_chk;

ALTER TABLE social_scope_chat_message
  ADD CONSTRAINT social_scope_chat_message_shared_entity_pair_chk
  CHECK (
    (shared_entity_type IS NULL AND shared_entity_id IS NULL)
    OR (shared_entity_type IS NOT NULL AND shared_entity_id IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_social_scope_chat_message_shared_entity
  ON social_scope_chat_message (shared_entity_type, shared_entity_id)
  WHERE shared_entity_type IS NOT NULL;

COMMIT;
