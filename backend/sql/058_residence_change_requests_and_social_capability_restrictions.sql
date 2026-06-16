BEGIN;

CREATE TABLE IF NOT EXISTS residence_change_request (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  current_snapshot_json JSONB NOT NULL,
  requested_snapshot_json JSONB NOT NULL,
  note TEXT,
  document_image_url TEXT,
  review_note TEXT,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT residence_change_request_status_check
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_residence_change_request_user_recent
  ON residence_change_request (user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_residence_change_request_status_recent
  ON residence_change_request (status, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_residence_change_request_pending_unique
  ON residence_change_request (user_id)
  WHERE status = 'pending';

DROP TRIGGER IF EXISTS trg_residence_change_request_updated ON residence_change_request;
CREATE TRIGGER trg_residence_change_request_updated
BEFORE UPDATE ON residence_change_request
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_capability_restriction (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  capability_key VARCHAR(40) NOT NULL,
  reason TEXT,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at TIMESTAMPTZ,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  revoked_at TIMESTAMPTZ,
  revoked_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_capability_restriction_capability_check
    CHECK (
      capability_key IN (
        'post_create',
        'story_create',
        'reel_create',
        'comment_create',
        'community_post_create'
      )
    ),
  CONSTRAINT social_capability_restriction_dates_check
    CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_social_capability_restriction_user_active
  ON social_capability_restriction (user_id, capability_key, starts_at DESC, id DESC)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_social_capability_restriction_active_window
  ON social_capability_restriction (capability_key, starts_at DESC, ends_at, revoked_at);

DROP TRIGGER IF EXISTS trg_social_capability_restriction_updated
  ON social_capability_restriction;
CREATE TRIGGER trg_social_capability_restriction_updated
BEFORE UPDATE ON social_capability_restriction
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS moderation_note TEXT;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS moderation_requested_at TIMESTAMPTZ;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS moderation_requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS social_story_report_review_log (
  id BIGSERIAL PRIMARY KEY,
  story_id BIGINT NOT NULL REFERENCES social_story(id) ON DELETE CASCADE,
  admin_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  action VARCHAR(32) NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_story_report_review_log_story
  ON social_story_report_review_log (story_id, id DESC);

COMMIT;
