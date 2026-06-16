BEGIN;

ALTER TABLE social_post_comment
  ADD COLUMN IF NOT EXISTS parent_comment_id BIGINT REFERENCES social_post_comment(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_social_post_comment_parent_recent
  ON social_post_comment (parent_comment_id, id DESC);

CREATE TABLE IF NOT EXISTS social_post_comment_like (
  post_comment_id BIGINT NOT NULL REFERENCES social_post_comment(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_post_comment_like_user_recent
  ON social_post_comment_like (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_post_report (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  reporter_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, reporter_user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_post_report_recent
  ON social_post_report (created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS social_story_like (
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_story_like_user_recent
  ON social_story_like (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_story_comment (
  id BIGSERIAL PRIMARY KEY,
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  edited_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_social_story_comment_story_recent
  ON social_story_comment (story_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_story_comment_user_recent
  ON social_story_comment (user_id, id DESC);

DROP TRIGGER IF EXISTS trg_social_story_comment_updated ON social_story_comment;
CREATE TRIGGER trg_social_story_comment_updated
BEFORE UPDATE ON social_story_comment
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_story_report (
  id BIGSERIAL PRIMARY KEY,
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  reporter_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (story_id, reporter_user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_story_report_recent
  ON social_story_report (created_at DESC, id DESC);

COMMIT;
