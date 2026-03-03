BEGIN;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS social_bio TEXT NOT NULL DEFAULT '';

ALTER TABLE app_user
DROP CONSTRAINT IF EXISTS app_user_social_bio_len_check;

ALTER TABLE app_user
ADD CONSTRAINT app_user_social_bio_len_check
CHECK (char_length(social_bio) <= 280);

CREATE TABLE IF NOT EXISTS social_story_highlight (
  id BIGSERIAL PRIMARY KEY,
  owner_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  title VARCHAR(60) NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_story_highlight_owner_story_unique
    UNIQUE (owner_user_id, story_id)
);

CREATE INDEX IF NOT EXISTS idx_social_story_highlight_owner_recent
  ON social_story_highlight (owner_user_id, id DESC);

DROP TRIGGER IF EXISTS trg_social_story_highlight_updated ON social_story_highlight;
CREATE TRIGGER trg_social_story_highlight_updated
BEFORE UPDATE ON social_story_highlight
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
