ALTER TABLE social_chat_thread_participant_state
  ADD COLUMN IF NOT EXISTS inbox_bucket TEXT NOT NULL DEFAULT 'primary',
  ADD COLUMN IF NOT EXISTS request_status TEXT NOT NULL DEFAULT 'accepted',
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

ALTER TABLE social_chat_thread_participant_state
  DROP CONSTRAINT IF EXISTS social_chat_thread_participant_state_inbox_bucket_chk;
ALTER TABLE social_chat_thread_participant_state
  ADD CONSTRAINT social_chat_thread_participant_state_inbox_bucket_chk
  CHECK (inbox_bucket IN ('primary', 'requests'));

ALTER TABLE social_chat_thread_participant_state
  DROP CONSTRAINT IF EXISTS social_chat_thread_participant_state_request_status_chk;
ALTER TABLE social_chat_thread_participant_state
  ADD CONSTRAINT social_chat_thread_participant_state_request_status_chk
  CHECK (request_status IN ('accepted', 'pending', 'rejected', 'blocked'));

UPDATE social_chat_thread_participant_state
SET accepted_at = COALESCE(accepted_at, created_at, NOW())
WHERE request_status = 'accepted'
  AND accepted_at IS NULL;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS shared_entity_type TEXT,
  ADD COLUMN IF NOT EXISTS shared_entity_id BIGINT,
  ADD COLUMN IF NOT EXISTS shared_snapshot_json JSONB;

ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_shared_entity_type_chk;
ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN ('post', 'reel', 'review')
  );

CREATE INDEX IF NOT EXISTS social_chat_thread_participant_bucket_idx
  ON social_chat_thread_participant_state (user_id, inbox_bucket, request_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS social_chat_message_shared_entity_idx
  ON social_chat_message (shared_entity_type, shared_entity_id)
  WHERE shared_entity_type IS NOT NULL;
