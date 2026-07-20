-- Additive session hardening for atomic refresh/recovery.
-- Idempotent by design: do not edit older published migrations.

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS device_session_id VARCHAR(80);

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS recovery_secret_hash VARCHAR(255);

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS app_surface VARCHAR(40);

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS refresh_generation INTEGER NOT NULL DEFAULT 0;

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS previous_refresh_token_hash VARCHAR(128);

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS previous_refresh_valid_until TIMESTAMPTZ;

ALTER TABLE user_session
  ADD COLUMN IF NOT EXISTS last_recovered_at TIMESTAMPTZ;

UPDATE user_session
SET refresh_generation = 0
WHERE refresh_generation IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_session_device_session_unique
  ON user_session (device_session_id)
  WHERE device_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_session_device_recovery_active
  ON user_session (device_session_id, is_revoked);

CREATE INDEX IF NOT EXISTS idx_user_session_recovery_lookup
  ON user_session (device_session_id, app_surface, is_revoked)
  WHERE device_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_session_previous_refresh_grace
  ON user_session (previous_refresh_token_hash, previous_refresh_valid_until)
  WHERE previous_refresh_token_hash IS NOT NULL;
