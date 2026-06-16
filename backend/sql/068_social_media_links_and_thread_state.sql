BEGIN;

CREATE TABLE IF NOT EXISTS social_media_asset (
  id BIGSERIAL PRIMARY KEY,
  owner_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  source_type VARCHAR(16) NOT NULL,
  media_kind VARCHAR(12) NOT NULL,
  original_url TEXT NOT NULL,
  normalized_url TEXT,
  poster_url TEXT,
  mime_type VARCHAR(180),
  duration_ms INTEGER,
  width INTEGER,
  height INTEGER,
  processing_status VARCHAR(16) NOT NULL DEFAULT 'ready',
  processing_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_media_asset_source_type_check
    CHECK (source_type IN ('post', 'story', 'reel')),
  CONSTRAINT social_media_asset_kind_check
    CHECK (media_kind IN ('image', 'video')),
  CONSTRAINT social_media_asset_processing_status_check
    CHECK (processing_status IN ('pending', 'processing', 'ready', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_social_media_asset_owner_recent
  ON social_media_asset (owner_user_id, created_at DESC, id DESC);

DROP TRIGGER IF EXISTS trg_social_media_asset_updated ON social_media_asset;
CREATE TRIGGER trg_social_media_asset_updated
BEFORE UPDATE ON social_media_asset
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS media_asset_id BIGINT REFERENCES social_media_asset(id) ON DELETE SET NULL;

ALTER TABLE social_story
  ADD COLUMN IF NOT EXISTS media_asset_id BIGINT REFERENCES social_media_asset(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS social_media_processing_job (
  id BIGSERIAL PRIMARY KEY,
  asset_id BIGINT NOT NULL REFERENCES social_media_asset(id) ON DELETE CASCADE,
  job_type VARCHAR(24) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_media_processing_job_status_check
    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  CONSTRAINT social_media_processing_job_type_check
    CHECK (job_type IN ('poster', 'normalize_video'))
);

CREATE INDEX IF NOT EXISTS idx_social_media_processing_job_asset_recent
  ON social_media_processing_job (asset_id, created_at DESC, id DESC);

DROP TRIGGER IF EXISTS trg_social_media_processing_job_updated ON social_media_processing_job;
CREATE TRIGGER trg_social_media_processing_job_updated
BEFORE UPDATE ON social_media_processing_job
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_content_link (
  id BIGSERIAL PRIMARY KEY,
  entity_type VARCHAR(16) NOT NULL,
  entity_id BIGINT NOT NULL,
  target_type VARCHAR(16) NOT NULL,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  product_id BIGINT REFERENCES product(id) ON DELETE SET NULL,
  offer_id BIGINT REFERENCES merchant_offer(id) ON DELETE SET NULL,
  coupon_id BIGINT REFERENCES coupon(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_content_link_entity_type_check
    CHECK (entity_type IN ('post', 'story', 'reel')),
  CONSTRAINT social_content_link_target_type_check
    CHECK (target_type IN ('merchant', 'product', 'offer', 'coupon'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_content_link_unique
  ON social_content_link (entity_type, entity_id);

CREATE TABLE IF NOT EXISTS social_chat_thread_participant_state (
  thread_id BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  last_read_message_id BIGINT REFERENCES social_chat_message(id) ON DELETE SET NULL,
  last_read_at TIMESTAMPTZ,
  last_delivered_message_id BIGINT REFERENCES social_chat_message(id) ON DELETE SET NULL,
  last_delivered_at TIMESTAMPTZ,
  muted_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (thread_id, user_id)
);

DROP TRIGGER IF EXISTS trg_social_chat_thread_participant_state_updated ON social_chat_thread_participant_state;
CREATE TRIGGER trg_social_chat_thread_participant_state_updated
BEFORE UPDATE ON social_chat_thread_participant_state
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
