-- ============================================================
-- 029 Jobs: activity/department + application decision reason
-- ============================================================

BEGIN;

ALTER TABLE job_post
  ADD COLUMN IF NOT EXISTS activity_type VARCHAR(80) NOT NULL DEFAULT 'general_business',
  ADD COLUMN IF NOT EXISTS department VARCHAR(120) NOT NULL DEFAULT 'operations';

CREATE INDEX IF NOT EXISTS idx_job_post_activity_type ON job_post(activity_type);
CREATE INDEX IF NOT EXISTS idx_job_post_department ON job_post(department);

ALTER TABLE job_application
  ADD COLUMN IF NOT EXISTS status_reason TEXT,
  ADD COLUMN IF NOT EXISTS status_changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_job_application_status_changed_by
  ON job_application(status_changed_by_user_id);

COMMIT;
