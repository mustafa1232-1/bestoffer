BEGIN;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS social_age SMALLINT;

ALTER TABLE app_user
DROP CONSTRAINT IF EXISTS app_user_social_age_check;

ALTER TABLE app_user
ADD CONSTRAINT app_user_social_age_check
CHECK (social_age IS NULL OR (social_age >= 13 AND social_age <= 100));

COMMIT;
