BEGIN;

ALTER TABLE social_post
  DROP CONSTRAINT IF EXISTS social_post_kind_check;

ALTER TABLE social_post
  ADD CONSTRAINT social_post_kind_check
  CHECK (post_kind IN ('text', 'image', 'video', 'reel', 'merchant_review'));

UPDATE social_post
SET post_kind = 'reel'
WHERE post_kind = 'video';

CREATE TABLE IF NOT EXISTS social_content_impression (
  id BIGSERIAL PRIMARY KEY,
  content_type VARCHAR(16) NOT NULL,
  content_id BIGINT NOT NULL,
  viewer_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  impression_context VARCHAR(32) NOT NULL DEFAULT 'feed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_content_impression_type_check
    CHECK (content_type IN ('post', 'story', 'reel'))
);

CREATE INDEX IF NOT EXISTS idx_social_content_impression_lookup
  ON social_content_impression (content_type, content_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_social_content_impression_viewer_recent
  ON social_content_impression (viewer_user_id, created_at DESC)
  WHERE viewer_user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS social_reel_view_event (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  viewer_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  watch_duration_ms INTEGER NOT NULL DEFAULT 0,
  completion_rate NUMERIC(5,2) NOT NULL DEFAULT 0,
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  replay_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_reel_view_event_duration_check
    CHECK (watch_duration_ms >= 0),
  CONSTRAINT social_reel_view_event_completion_rate_check
    CHECK (completion_rate >= 0 AND completion_rate <= 100),
  CONSTRAINT social_reel_view_event_replay_count_check
    CHECK (replay_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_social_reel_view_event_post_recent
  ON social_reel_view_event (post_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_social_reel_view_event_viewer_recent
  ON social_reel_view_event (viewer_user_id, created_at DESC)
  WHERE viewer_user_id IS NOT NULL;

COMMIT;
