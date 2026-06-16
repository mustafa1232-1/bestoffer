-- ============================================================
-- 030 User work profile fields
-- ============================================================

BEGIN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS work_title VARCHAR(160),
  ADD COLUMN IF NOT EXISTS work_company VARCHAR(180);

COMMIT;
