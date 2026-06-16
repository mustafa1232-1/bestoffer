BEGIN;

ALTER TABLE social_chat_thread_participant_state
  ADD COLUMN IF NOT EXISTS theme_key VARCHAR(32) NOT NULL DEFAULT 'default';

CREATE TABLE IF NOT EXISTS social_chat_message_translation (
  id BIGSERIAL PRIMARY KEY,
  message_id BIGINT NOT NULL REFERENCES social_chat_message(id) ON DELETE CASCADE,
  target_language VARCHAR(12) NOT NULL,
  source_language VARCHAR(12),
  translated_text TEXT NOT NULL,
  provider VARCHAR(32) NOT NULL DEFAULT 'openai',
  model_name VARCHAR(120),
  source_version_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_chat_message_translation_unique
    UNIQUE (message_id, target_language)
);

CREATE INDEX IF NOT EXISTS idx_social_chat_message_translation_lookup
  ON social_chat_message_translation (message_id, target_language, updated_at DESC);

DROP TRIGGER IF EXISTS trg_social_chat_message_translation_updated
  ON social_chat_message_translation;
CREATE TRIGGER trg_social_chat_message_translation_updated
BEFORE UPDATE ON social_chat_message_translation
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
