BEGIN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS analytics_consent_granted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS analytics_consent_granted_at TIMESTAMPTZ;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS chat_quality_review_consent BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE app_user
SET chat_quality_review_consent = TRUE
WHERE analytics_consent_granted = TRUE
  AND chat_quality_review_consent = FALSE;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS reply_to_message_id BIGINT REFERENCES social_chat_message(id) ON DELETE SET NULL;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_kind VARCHAR(16);

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_name TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_mime_type VARCHAR(160);

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_size_bytes INTEGER;

ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_attachment_kind_check;

ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_attachment_kind_check
  CHECK (
    attachment_kind IS NULL
    OR attachment_kind IN ('image', 'video', 'file')
  );

CREATE INDEX IF NOT EXISTS idx_social_chat_message_reply
  ON social_chat_message (reply_to_message_id)
  WHERE reply_to_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app_user_chat_quality_review_consent
  ON app_user (chat_quality_review_consent, id DESC);

COMMIT;
