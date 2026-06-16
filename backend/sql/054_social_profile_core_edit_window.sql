BEGIN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_profile_core_updated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_app_user_social_profile_core_updated_at
ON app_user(social_profile_core_updated_at DESC NULLS LAST);

COMMIT;
