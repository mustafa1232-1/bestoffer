BEGIN;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS audience_scope_type VARCHAR(16) NOT NULL DEFAULT 'global';

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS audience_scope_code VARCHAR(16);

UPDATE social_post
SET audience_scope_type = 'global'
WHERE TRIM(COALESCE(audience_scope_type, '')) = '';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'social_post_audience_scope_type_check'
  ) THEN
    ALTER TABLE social_post
      ADD CONSTRAINT social_post_audience_scope_type_check
      CHECK (audience_scope_type IN ('global', 'block', 'compound', 'building'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_social_post_scope_recent
  ON social_post (audience_scope_type, audience_scope_code, id DESC);

COMMIT;
