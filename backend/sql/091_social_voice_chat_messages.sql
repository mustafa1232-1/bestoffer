BEGIN;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_duration_ms INTEGER;

ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_attachment_kind_check;

ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_attachment_kind_check
  CHECK (
    attachment_kind IS NULL
    OR attachment_kind IN ('image', 'video', 'audio', 'file')
  );

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_kind VARCHAR(16);

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_name TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_mime_type VARCHAR(160);

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_size_bytes INTEGER;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_duration_ms INTEGER;

ALTER TABLE social_scope_chat_message
  DROP CONSTRAINT IF EXISTS social_scope_chat_message_attachment_kind_check;

ALTER TABLE social_scope_chat_message
  ADD CONSTRAINT social_scope_chat_message_attachment_kind_check
  CHECK (
    attachment_kind IS NULL
    OR attachment_kind IN ('image', 'video', 'audio', 'file')
  );

COMMIT;
