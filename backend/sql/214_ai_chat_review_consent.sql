ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS ai_chat_review_consent BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_app_user_ai_chat_review_consent
  ON app_user (ai_chat_review_consent, id DESC);
