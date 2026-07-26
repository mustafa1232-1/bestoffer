BEGIN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS account_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS account_deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS account_deletion_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS account_deletion_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS account_deletion_status VARCHAR(24) NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS account_deletion_note TEXT,
  ADD COLUMN IF NOT EXISTS account_deletion_retention_policy_version VARCHAR(32);

UPDATE app_user
SET account_deletion_status = 'none'
WHERE account_deletion_status IS NULL;

CREATE INDEX IF NOT EXISTS idx_app_user_account_deleted
  ON app_user (account_deleted, account_deleted_at);

CREATE INDEX IF NOT EXISTS idx_app_user_active_not_deleted
  ON app_user (role, is_account_disabled, account_deleted)
  WHERE COALESCE(account_deleted, FALSE) = FALSE;

COMMIT;
