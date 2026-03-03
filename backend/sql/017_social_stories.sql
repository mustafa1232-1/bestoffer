BEGIN;

CREATE TABLE IF NOT EXISTS social_story (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  caption TEXT,
  media_url TEXT,
  media_kind VARCHAR(12),
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'approved',
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_story_media_kind_check
    CHECK (media_kind IS NULL OR media_kind IN ('image', 'video')),
  CONSTRAINT social_story_moderation_status_check
    CHECK (moderation_status IN ('approved', 'rejected', 'pending'))
);

CREATE INDEX IF NOT EXISTS idx_social_story_active
  ON social_story (is_deleted, moderation_status, expires_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_story_user_recent
  ON social_story (user_id, id DESC);

DROP TRIGGER IF EXISTS trg_social_story_updated ON social_story;
CREATE TRIGGER trg_social_story_updated
BEFORE UPDATE ON social_story
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_story_view (
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_story_view_user
  ON social_story_view (user_id, viewed_at DESC);

COMMIT;
