-- ============================================================
-- 056 Jobs: extended application lifecycle + status history
-- ============================================================

BEGIN;

ALTER TABLE IF EXISTS job_application
  DROP CONSTRAINT IF EXISTS job_application_status_check;

ALTER TABLE IF EXISTS job_application
  ADD CONSTRAINT job_application_status_check
  CHECK (
    status IN (
      'submitted',
      'shortlisted',
      'rejected',
      'hired',
      'withdrawn',
      'dismissed_after_hire',
      'archived'
    )
  );

CREATE TABLE IF NOT EXISTS job_application_status_history (
  id BIGSERIAL PRIMARY KEY,
  application_id BIGINT NOT NULL REFERENCES job_application(id) ON DELETE CASCADE,
  job_id BIGINT NOT NULL REFERENCES job_post(id) ON DELETE CASCADE,
  previous_status VARCHAR(40),
  next_status VARCHAR(40) NOT NULL,
  reason TEXT,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_job_application_status_history_application
  ON job_application_status_history(application_id, changed_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_job_application_status_history_job
  ON job_application_status_history(job_id, changed_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_job_application_status_history_status
  ON job_application_status_history(next_status);

CREATE OR REPLACE FUNCTION sync_job_application_status_history()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO job_application_status_history (
      application_id,
      job_id,
      previous_status,
      next_status,
      reason,
      changed_by_user_id,
      changed_at
    )
    VALUES (
      NEW.id,
      NEW.job_id,
      NULL,
      NEW.status,
      NEW.status_reason,
      NEW.status_changed_by_user_id,
      COALESCE(NEW.status_changed_at, NEW.created_at, NOW())
    );
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO job_application_status_history (
      application_id,
      job_id,
      previous_status,
      next_status,
      reason,
      changed_by_user_id,
      changed_at
    )
    VALUES (
      NEW.id,
      NEW.job_id,
      OLD.status,
      NEW.status,
      NEW.status_reason,
      NEW.status_changed_by_user_id,
      COALESCE(NEW.status_changed_at, NOW())
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_job_application_status_history ON job_application;
CREATE TRIGGER trg_job_application_status_history
AFTER INSERT OR UPDATE OF status, status_reason, status_changed_by_user_id, status_changed_at
ON job_application
FOR EACH ROW
EXECUTE FUNCTION sync_job_application_status_history();

INSERT INTO job_application_status_history (
  application_id,
  job_id,
  previous_status,
  next_status,
  reason,
  changed_by_user_id,
  changed_at
)
SELECT
  a.id,
  a.job_id,
  NULL,
  a.status,
  a.status_reason,
  a.status_changed_by_user_id,
  COALESCE(a.status_changed_at, a.created_at, NOW())
FROM job_application a
WHERE NOT EXISTS (
  SELECT 1
  FROM job_application_status_history h
  WHERE h.application_id = a.id
);

COMMIT;
