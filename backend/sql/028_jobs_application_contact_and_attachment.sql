-- ============================================================
-- 028 Jobs application: email + attachment metadata
-- ============================================================

BEGIN;

ALTER TABLE job_application
  ADD COLUMN IF NOT EXISTS applicant_email VARCHAR(180),
  ADD COLUMN IF NOT EXISTS attachment_url TEXT,
  ADD COLUMN IF NOT EXISTS attachment_mime VARCHAR(120),
  ADD COLUMN IF NOT EXISTS attachment_name VARCHAR(255);

COMMIT;
