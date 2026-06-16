BEGIN;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS is_account_disabled BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS failed_login_attempts SMALLINT NOT NULL DEFAULT 0;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS last_failed_login_at TIMESTAMPTZ;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS token_jti VARCHAR(80);

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS device_fingerprint VARCHAR(128);

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS is_revoked BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS revoked_reason VARCHAR(80);

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS access_expires_at TIMESTAMPTZ;

ALTER TABLE user_session
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE user_session
SET is_revoked = FALSE
WHERE is_revoked IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_session_user_active
  ON user_session (user_id, is_revoked, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_session_user_device
  ON user_session (user_id, device_fingerprint, is_revoked);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_session_token_jti_unique
  ON user_session (token_jti)
  WHERE token_jti IS NOT NULL;

COMMIT;
