ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS account_disabled_note TEXT,
  ADD COLUMN IF NOT EXISTS account_disabled_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS account_disabled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS account_enabled_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS account_enabled_at TIMESTAMPTZ;
