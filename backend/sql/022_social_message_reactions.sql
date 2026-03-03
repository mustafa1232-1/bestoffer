BEGIN;

CREATE TABLE IF NOT EXISTS social_chat_message_reaction (
  id          BIGSERIAL PRIMARY KEY,
  message_id  BIGINT NOT NULL REFERENCES social_chat_message(id) ON DELETE CASCADE,
  user_id     BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reaction    VARCHAR(16) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_chat_message_reaction_kind_check
    CHECK (reaction IN ('like', 'heart', 'laugh', 'fire')),
  CONSTRAINT social_chat_message_reaction_unique_per_user
    UNIQUE (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_chat_message_reaction_message
  ON social_chat_message_reaction (message_id, reaction, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_social_chat_message_reaction_user
  ON social_chat_message_reaction (user_id, updated_at DESC);

DROP TRIGGER IF EXISTS trg_social_chat_message_reaction_updated ON social_chat_message_reaction;
CREATE TRIGGER trg_social_chat_message_reaction_updated
BEFORE UPDATE ON social_chat_message_reaction
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
