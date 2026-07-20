-- Separate taxi captain approval state from delivery courier approval.
-- Additive and idempotent; keeps existing accounts compatible.

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS taxi_account_approved BOOLEAN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS taxi_approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS taxi_approved_at TIMESTAMPTZ;

UPDATE app_user
SET taxi_account_approved = delivery_account_approved
WHERE role = 'taxi_captain'
  AND taxi_account_approved IS NULL;

UPDATE app_user
SET taxi_account_approved = TRUE
WHERE role <> 'taxi_captain'
  AND taxi_account_approved IS NULL;

ALTER TABLE app_user
  ALTER COLUMN taxi_account_approved SET DEFAULT TRUE;

ALTER TABLE app_user
  ALTER COLUMN taxi_account_approved SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app_user_taxi_approval
  ON app_user (role, taxi_account_approved)
  WHERE role = 'taxi_captain';
