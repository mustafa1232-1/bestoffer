BEGIN;

CREATE TABLE IF NOT EXISTS social_saved_collection (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  title VARCHAR(120) NOT NULL,
  description TEXT,
  system_key VARCHAR(32),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_saved_collection_user_recent
  ON social_saved_collection (user_id, updated_at DESC, id DESC);

DROP TRIGGER IF EXISTS trg_social_saved_collection_updated ON social_saved_collection;
CREATE TRIGGER trg_social_saved_collection_updated
BEFORE UPDATE ON social_saved_collection
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_saved_item (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  entity_type VARCHAR(16) NOT NULL,
  entity_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_saved_item_type_check
    CHECK (entity_type IN ('post', 'reel', 'review')),
  CONSTRAINT social_saved_item_unique UNIQUE (user_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_social_saved_item_user_recent
  ON social_saved_item (user_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS social_saved_collection_item (
  collection_id BIGINT NOT NULL REFERENCES social_saved_collection(id) ON DELETE CASCADE,
  saved_item_id BIGINT NOT NULL REFERENCES social_saved_item(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (collection_id, saved_item_id)
);

CREATE INDEX IF NOT EXISTS idx_social_saved_collection_item_recent
  ON social_saved_collection_item (saved_item_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_hashtag (
  id BIGSERIAL PRIMARY KEY,
  tag VARCHAR(80) NOT NULL,
  normalized_tag VARCHAR(80) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_hashtag_tag
  ON social_hashtag (normalized_tag);

CREATE TABLE IF NOT EXISTS social_entity_hashtag (
  id BIGSERIAL PRIMARY KEY,
  hashtag_id BIGINT NOT NULL REFERENCES social_hashtag(id) ON DELETE CASCADE,
  entity_type VARCHAR(16) NOT NULL,
  entity_id BIGINT NOT NULL,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_entity_hashtag_type_check
    CHECK (entity_type IN ('post', 'story', 'comment'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_entity_hashtag_unique
  ON social_entity_hashtag (hashtag_id, entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_social_entity_hashtag_entity
  ON social_entity_hashtag (entity_type, entity_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_mention (
  id BIGSERIAL PRIMARY KEY,
  entity_type VARCHAR(16) NOT NULL,
  entity_id BIGINT NOT NULL,
  mentioned_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  mentioned_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  display_label VARCHAR(180),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notification_sent_at TIMESTAMPTZ,
  CONSTRAINT social_mention_type_check
    CHECK (entity_type IN ('post', 'story', 'comment'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_mention_unique
  ON social_mention (entity_type, entity_id, mentioned_user_id);

CREATE INDEX IF NOT EXISTS idx_social_mention_user_recent
  ON social_mention (mentioned_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_search_recent (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  search_type VARCHAR(16) NOT NULL,
  raw_query VARCHAR(160) NOT NULL,
  normalized_query VARCHAR(160) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_search_recent_type_check
    CHECK (search_type IN ('all', 'users', 'posts', 'reels', 'hashtags', 'merchants', 'reviews'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_search_recent_unique
  ON social_search_recent (user_id, search_type, normalized_query);

CREATE INDEX IF NOT EXISTS idx_social_search_recent_user_recent
  ON social_search_recent (user_id, updated_at DESC, id DESC);

DROP TRIGGER IF EXISTS trg_social_search_recent_updated ON social_search_recent;
CREATE TRIGGER trg_social_search_recent_updated
BEFORE UPDATE ON social_search_recent
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
