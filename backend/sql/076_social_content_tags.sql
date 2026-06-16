CREATE TABLE IF NOT EXISTS social_content_tag (
  id BIGSERIAL PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id BIGINT NOT NULL,
  tagged_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  tagged_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_content_tag_entity_type_chk
    CHECK (entity_type IN ('post', 'reel')),
  CONSTRAINT social_content_tag_unique_target
    UNIQUE (entity_type, entity_id, tagged_user_id)
);

CREATE INDEX IF NOT EXISTS social_content_tag_user_idx
  ON social_content_tag (tagged_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS social_content_tag_entity_idx
  ON social_content_tag (entity_type, entity_id, created_at DESC);

INSERT INTO social_content_tag (entity_type, entity_id, tagged_user_id, tagged_by_user_id, created_at)
SELECT DISTINCT
  CASE WHEN p.post_kind = 'reel' THEN 'reel' ELSE 'post' END AS entity_type,
  sm.entity_id,
  sm.mentioned_user_id,
  sm.mentioned_by_user_id,
  COALESCE(sm.created_at, NOW())
FROM social_mention sm
JOIN social_post p ON p.id = sm.entity_id
WHERE sm.entity_type = 'post'
  AND sm.mentioned_user_id IS NOT NULL
  AND sm.mentioned_by_user_id IS NOT NULL
ON CONFLICT (entity_type, entity_id, tagged_user_id) DO NOTHING;
