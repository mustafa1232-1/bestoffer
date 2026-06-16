BEGIN;

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS social_relations_public BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE app_user
SET social_relations_public = TRUE
WHERE social_relations_public IS NULL;

COMMIT;
