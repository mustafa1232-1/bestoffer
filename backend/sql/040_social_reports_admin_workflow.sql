ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_violation_strikes INTEGER;

UPDATE app_user
SET social_violation_strikes = 0
WHERE social_violation_strikes IS NULL;

ALTER TABLE app_user
  ALTER COLUMN social_violation_strikes SET DEFAULT 0;

ALTER TABLE app_user
  ALTER COLUMN social_violation_strikes SET NOT NULL;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_write_block_until TIMESTAMPTZ;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_visibility_tier VARCHAR(20);

UPDATE app_user
SET social_visibility_tier = 'normal'
WHERE social_visibility_tier IS NULL
   OR TRIM(COALESCE(social_visibility_tier, '')) = '';

ALTER TABLE app_user
  ALTER COLUMN social_visibility_tier SET DEFAULT 'normal';

ALTER TABLE app_user
  ALTER COLUMN social_visibility_tier SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'app_user_social_visibility_tier_check'
  ) THEN
    ALTER TABLE app_user
      ADD CONSTRAINT app_user_social_visibility_tier_check
      CHECK (social_visibility_tier IN ('normal', 'gray_zone'));
  END IF;
END $$;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_false_reports_count INTEGER;

UPDATE app_user
SET social_false_reports_count = 0
WHERE social_false_reports_count IS NULL;

ALTER TABLE app_user
  ALTER COLUMN social_false_reports_count SET DEFAULT 0;

ALTER TABLE app_user
  ALTER COLUMN social_false_reports_count SET NOT NULL;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_reports_blocked BOOLEAN;

UPDATE app_user
SET social_reports_blocked = FALSE
WHERE social_reports_blocked IS NULL;

ALTER TABLE app_user
  ALTER COLUMN social_reports_blocked SET DEFAULT FALSE;

ALTER TABLE app_user
  ALTER COLUMN social_reports_blocked SET NOT NULL;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS moderation_note TEXT;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS moderation_requested_at TIMESTAMPTZ;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS moderation_requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS social_user_report (
  id BIGSERIAL PRIMARY KEY,
  reported_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reporter_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (reported_user_id, reporter_user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_user_report_recent
  ON social_user_report (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_user_report_reported_user
  ON social_user_report (reported_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_post_report_review_log (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  admin_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  action VARCHAR(32) NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_post_report_review_log_post
  ON social_post_report_review_log (post_id, id DESC);
