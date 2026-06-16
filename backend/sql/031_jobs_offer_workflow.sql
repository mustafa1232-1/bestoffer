-- ============================================================
-- 031 Jobs offer workflow (hire offer + applicant acceptance)
-- ============================================================

BEGIN;

ALTER TABLE job_application
  ADD COLUMN IF NOT EXISTS offer_salary NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS offer_work_hours VARCHAR(180),
  ADD COLUMN IF NOT EXISTS offer_work_days VARCHAR(180),
  ADD COLUMN IF NOT EXISTS offer_message TEXT,
  ADD COLUMN IF NOT EXISTS offer_attachment_url TEXT,
  ADD COLUMN IF NOT EXISTS offer_attachment_mime VARCHAR(120),
  ADD COLUMN IF NOT EXISTS offer_attachment_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS offer_sent_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS offer_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS offer_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS offer_acceptance_attachment_url TEXT,
  ADD COLUMN IF NOT EXISTS offer_acceptance_attachment_mime VARCHAR(120),
  ADD COLUMN IF NOT EXISTS offer_acceptance_attachment_name VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_job_application_offer_sent_at
  ON job_application(offer_sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_job_application_offer_accepted_at
  ON job_application(offer_accepted_at DESC);

COMMIT;
