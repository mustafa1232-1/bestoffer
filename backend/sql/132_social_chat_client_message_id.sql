BEGIN;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS client_message_id TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS client_message_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS social_chat_message_client_message_id_unique
  ON social_chat_message (thread_id, sender_user_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS social_scope_chat_message_client_message_id_unique
  ON social_scope_chat_message (scope_type, scope_code, sender_user_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

COMMIT;
