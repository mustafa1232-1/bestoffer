-- Social V3 §2: authoritative audience scope for stories.
--
-- Mirrors 116c (social_post audience scope). Adds scope columns to social_story
-- so building/block/compound stories can be persisted and enforced server-side
-- instead of being silently published globally. Idempotent and non-destructive:
-- existing stories default to 'global'; no rows are deleted or altered in a way
-- that affects legacy R2 media playback.
--
-- Allowed scope types intentionally match the authoritative community scope
-- model (normalizeCommunityScope): global | block | compound | building.
-- Relationship scopes (followers/close_friends/area/custom) are NOT added here
-- because no backend visibility model exists for them.
--
-- Rollback: DROP the two constraints, the index, and the three columns. No data
-- loss beyond the scope metadata itself (stories revert to global visibility).

BEGIN;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS audience_scope_type VARCHAR(16) NOT NULL DEFAULT 'global',
  ADD COLUMN IF NOT EXISTS audience_scope_code VARCHAR(16),
  ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE social_story
SET audience_scope_type = 'global'
WHERE TRIM(COALESCE(audience_scope_type, '')) = '';

-- Allowed scope types.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'social_story_audience_scope_type_check'
  ) THEN
    ALTER TABLE social_story
      ADD CONSTRAINT social_story_audience_scope_type_check
      CHECK (audience_scope_type IN ('global', 'block', 'compound', 'building'));
  END IF;
END $$;

-- Scope consistency: a non-global scope must carry a code; global must not.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'social_story_audience_scope_code_check'
  ) THEN
    ALTER TABLE social_story
      ADD CONSTRAINT social_story_audience_scope_code_check
      CHECK (
        (audience_scope_type = 'global' AND audience_scope_code IS NULL)
        OR (audience_scope_type <> 'global' AND audience_scope_code IS NOT NULL)
      );
  END IF;
END $$;

-- Active scoped-story retrieval index (matches the story read pattern).
CREATE INDEX IF NOT EXISTS idx_social_story_scope_active
  ON social_story (
    is_deleted,
    moderation_status,
    audience_scope_type,
    audience_scope_code,
    expires_at DESC,
    id DESC
  );

COMMIT;
