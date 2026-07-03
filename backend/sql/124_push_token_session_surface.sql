ALTER TABLE user_push_token
  ADD COLUMN IF NOT EXISTS locale VARCHAR(8),
  ADD COLUMN IF NOT EXISTS auth_session_id BIGINT NULL REFERENCES user_session(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS app_surface VARCHAR(24),
  ADD COLUMN IF NOT EXISTS device_fingerprint TEXT;

UPDATE user_push_token
SET is_active = FALSE,
    updated_at = NOW()
WHERE auth_session_id IS NULL
   OR app_surface IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_push_token_user_surface_active
  ON user_push_token(user_id, app_surface, is_active);

CREATE INDEX IF NOT EXISTS idx_user_push_token_session_active
  ON user_push_token(auth_session_id, is_active);
