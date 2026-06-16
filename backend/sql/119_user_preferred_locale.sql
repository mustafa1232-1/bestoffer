ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS preferred_locale VARCHAR(8);

UPDATE app_user
SET preferred_locale = LOWER(TRIM(COALESCE(preferred_locale, '')))
WHERE preferred_locale IS NOT NULL;

UPDATE app_user
SET preferred_locale = 'ar'
WHERE COALESCE(TRIM(preferred_locale), '') = ''
   OR preferred_locale NOT IN ('ar', 'en');

ALTER TABLE app_user
  ALTER COLUMN preferred_locale SET DEFAULT 'ar';

ALTER TABLE app_user
  ALTER COLUMN preferred_locale SET NOT NULL;
