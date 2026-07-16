BEGIN;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS shared_entity_type VARCHAR(32);

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS shared_entity_id BIGINT;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS shared_snapshot_json JSONB;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'social_post_shared_entity_type_chk'
  ) THEN
    ALTER TABLE social_post
      ADD CONSTRAINT social_post_shared_entity_type_chk
      CHECK (
        shared_entity_type IS NULL
        OR shared_entity_type IN ('post', 'reel', 'review')
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS social_post_shared_entity_idx
  ON social_post (shared_entity_type, shared_entity_id)
  WHERE shared_entity_type IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS social_post_owner_shared_entity_unique_idx
  ON social_post (user_id, post_kind, shared_entity_type, shared_entity_id)
  WHERE is_deleted = FALSE
    AND shared_entity_type IS NOT NULL
    AND shared_entity_id IS NOT NULL;

COMMIT;
