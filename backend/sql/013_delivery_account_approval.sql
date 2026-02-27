BEGIN;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS delivery_account_approved BOOLEAN;

UPDATE app_user
SET delivery_account_approved = TRUE
WHERE delivery_account_approved IS NULL;

ALTER TABLE app_user
ALTER COLUMN delivery_account_approved SET DEFAULT TRUE;

ALTER TABLE app_user
ALTER COLUMN delivery_account_approved SET NOT NULL;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS delivery_approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS delivery_approved_at TIMESTAMPTZ;

COMMIT;

