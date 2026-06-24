CREATE TABLE IF NOT EXISTS social_post_media (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  sort_order INT NOT NULL DEFAULT 0,
  media_url TEXT NOT NULL,
  media_kind TEXT NOT NULL,
  media_asset_id BIGINT REFERENCES social_media_asset(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_post_media_post
ON social_post_media (post_id, sort_order, id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_social_post_media_post_sort
ON social_post_media (post_id, sort_order);

INSERT INTO social_post_media (post_id, sort_order, media_url, media_kind, media_asset_id)
SELECT p.id, 0, p.media_url, p.media_kind, p.media_asset_id
FROM social_post p
WHERE p.media_url IS NOT NULL
  AND COALESCE(p.media_kind, '') <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM social_post_media pm
    WHERE pm.post_id = p.id
  );
