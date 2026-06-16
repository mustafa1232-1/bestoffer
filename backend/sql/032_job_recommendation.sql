-- ============================================================
-- 032 Job recommendations by admin/super-admin
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS job_recommendation (
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES job_post(id) ON DELETE CASCADE,
  recommended_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  recommended_by_role user_role NOT NULL,
  source_application_id BIGINT REFERENCES job_application(id) ON DELETE SET NULL,
  candidate_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  candidate_full_name VARCHAR(180) NOT NULL,
  candidate_phone VARCHAR(30),
  candidate_email VARCHAR(180),
  candidate_work_title VARCHAR(160),
  candidate_work_company VARCHAR(180),
  recommendation_note TEXT,
  attachment_url TEXT,
  attachment_mime VARCHAR(120),
  attachment_name VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_job_recommendation_job
  ON job_recommendation(job_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_job_recommendation_candidate_user
  ON job_recommendation(candidate_user_id);

CREATE INDEX IF NOT EXISTS idx_job_recommendation_source_application
  ON job_recommendation(source_application_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_job_recommendation_source
  ON job_recommendation(job_id, source_application_id)
  WHERE source_application_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_job_recommendation_recommended_by
  ON job_recommendation(recommended_by_user_id);

COMMIT;
