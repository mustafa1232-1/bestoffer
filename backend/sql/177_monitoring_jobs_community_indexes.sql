BEGIN;

CREATE INDEX IF NOT EXISTS idx_job_post_monitoring_status_updated
  ON job_post (status, updated_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_job_post_monitoring_city_area
  ON job_post (city, area, status, updated_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_job_application_monitoring_job_status
  ON job_application (job_id, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_post_monitoring_user_kind
  ON social_post (user_id, post_kind, is_deleted, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_story_monitoring_user
  ON social_story (user_id, is_deleted, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_user_report_monitoring_reported
  ON social_user_report (reported_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_capability_restriction_monitoring_user
  ON social_capability_restriction (user_id, revoked_at, ends_at, created_at DESC, id DESC);

COMMIT;
