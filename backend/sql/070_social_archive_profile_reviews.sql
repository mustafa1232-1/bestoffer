BEGIN;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS archived_by_owner_at TIMESTAMPTZ;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS archived_by_owner_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_social_post_owner_archive
  ON social_post (user_id, archived_by_owner_at DESC, id DESC)
  WHERE archived_by_owner_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_social_post_visible_recent
  ON social_post (user_id, id DESC)
  WHERE is_deleted = FALSE
    AND moderation_status = 'approved'
    AND archived_by_owner_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_social_story_owner_archive
  ON social_story (user_id, archived_by_owner_at DESC, id DESC)
  WHERE archived_by_owner_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_social_story_visible_recent
  ON social_story (user_id, id DESC)
  WHERE is_deleted = FALSE
    AND moderation_status = 'approved'
    AND archived_by_owner_at IS NULL;

COMMIT;
