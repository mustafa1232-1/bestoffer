BEGIN;

ALTER TABLE social_chat_thread_participant_state
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_participant_state_pinned
  ON social_chat_thread_participant_state (user_id, pinned_at DESC, updated_at DESC)
  WHERE pinned_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS social_chat_thread_pinned_message (
  thread_id BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  message_id BIGINT NOT NULL REFERENCES social_chat_message(id) ON DELETE CASCADE,
  pinned_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  pinned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (thread_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_pinned_message_thread
  ON social_chat_thread_pinned_message (thread_id, pinned_at DESC, message_id DESC);

COMMIT;
