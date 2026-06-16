ALTER TABLE social_chat_thread
  ADD COLUMN IF NOT EXISTS thread_kind TEXT NOT NULL DEFAULT 'private',
  ADD COLUMN IF NOT EXISTS context_type TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS context_id BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS context_status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS context_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE social_chat_thread
SET thread_kind = 'private',
    context_type = 'none',
    context_id = 0,
    context_status = 'active',
    context_snapshot_json = COALESCE(context_snapshot_json, '{}'::jsonb)
WHERE thread_kind IS DISTINCT FROM 'private'
   OR context_type IS DISTINCT FROM 'none'
   OR context_id IS DISTINCT FROM 0
   OR context_status IS NULL
   OR context_snapshot_json IS NULL;

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_pair_unique;

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_kind_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_kind_chk
  CHECK (thread_kind IN ('private', 'business'));

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_context_type_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_context_type_chk
  CHECK (context_type IN ('none', 'car_listing', 'real_estate_listing'));

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_context_shape_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_context_shape_chk
  CHECK (
    (thread_kind = 'private' AND context_type = 'none' AND context_id = 0)
    OR
    (thread_kind = 'business' AND context_type <> 'none' AND context_id > 0)
  );

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_context_status_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_context_status_chk
  CHECK (
    context_status IN (
      'active',
      'sold',
      'rented',
      'archived',
      'hidden_due_subscription_expiry',
      'unavailable',
      'deleted'
    )
  );

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_unique_context;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_unique_context
  UNIQUE (user_a_id, user_b_id, thread_kind, context_type, context_id);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_kind_last
  ON social_chat_thread (thread_kind, last_message_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_context_lookup
  ON social_chat_thread (context_type, context_id, last_message_at DESC, id DESC)
  WHERE thread_kind = 'business';
