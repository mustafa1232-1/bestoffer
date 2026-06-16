BEGIN;

-- Auth/session hot paths used by access-auth middleware and session restore.
CREATE INDEX IF NOT EXISTS idx_user_session_active_user
ON user_session (user_id, is_revoked, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_session_active_session
ON user_session (id, user_id, is_revoked, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_session_token_jti
ON user_session (token_jti)
WHERE token_jti IS NOT NULL;

-- Guard login and role restore lookups.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_user'
      AND column_name = 'phone_normalized'
  ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_app_user_phone_normalized_runtime ON app_user (phone_normalized)';
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_user'
      AND column_name = 'delivery_account_approved'
  ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_app_user_role_enabled ON app_user (role, is_account_disabled, delivery_account_approved)';
  END IF;
END
$$;

COMMIT;
