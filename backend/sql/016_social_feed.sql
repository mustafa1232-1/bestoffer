BEGIN;

CREATE TABLE IF NOT EXISTS social_post (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  post_kind VARCHAR(24) NOT NULL DEFAULT 'text',
  caption TEXT,
  media_url TEXT,
  media_kind VARCHAR(12),
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  review_rating SMALLINT,
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'approved',
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_post_kind_check
    CHECK (post_kind IN ('text', 'image', 'video', 'merchant_review')),
  CONSTRAINT social_post_media_kind_check
    CHECK (media_kind IS NULL OR media_kind IN ('image', 'video')),
  CONSTRAINT social_post_review_rating_check
    CHECK (review_rating IS NULL OR (review_rating >= 1 AND review_rating <= 5)),
  CONSTRAINT social_post_moderation_status_check
    CHECK (moderation_status IN ('approved', 'rejected', 'pending'))
);

CREATE INDEX IF NOT EXISTS idx_social_post_recent
  ON social_post (id DESC);

CREATE INDEX IF NOT EXISTS idx_social_post_user_recent
  ON social_post (user_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_post_kind_recent
  ON social_post (post_kind, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_post_active
  ON social_post (is_deleted, moderation_status, id DESC);

DROP TRIGGER IF EXISTS trg_social_post_updated ON social_post;
CREATE TRIGGER trg_social_post_updated
BEFORE UPDATE ON social_post
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_post_like (
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_post_like_user
  ON social_post_like (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_post_comment (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES social_post(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'approved',
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_post_comment_moderation_status_check
    CHECK (moderation_status IN ('approved', 'rejected', 'pending'))
);

CREATE INDEX IF NOT EXISTS idx_social_post_comment_post_recent
  ON social_post_comment (post_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_post_comment_user_recent
  ON social_post_comment (user_id, id DESC);

DROP TRIGGER IF EXISTS trg_social_post_comment_updated ON social_post_comment;
CREATE TRIGGER trg_social_post_comment_updated
BEFORE UPDATE ON social_post_comment
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_chat_thread (
  id BIGSERIAL PRIMARY KEY,
  user_a_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  user_b_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_chat_thread_distinct_users_check
    CHECK (user_a_id <> user_b_id),
  CONSTRAINT social_chat_thread_order_check
    CHECK (user_a_id < user_b_id),
  CONSTRAINT social_chat_thread_pair_unique
    UNIQUE (user_a_id, user_b_id)
);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_user_a_last
  ON social_chat_thread (user_a_id, last_message_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_user_b_last
  ON social_chat_thread (user_b_id, last_message_at DESC, id DESC);

DROP TRIGGER IF EXISTS trg_social_chat_thread_updated ON social_chat_thread;
CREATE TRIGGER trg_social_chat_thread_updated
BEFORE UPDATE ON social_chat_thread
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_chat_message (
  id BIGSERIAL PRIMARY KEY,
  thread_id BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  sender_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_chat_message_thread_recent
  ON social_chat_message (thread_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_chat_message_sender_recent
  ON social_chat_message (sender_user_id, id DESC);

DROP TRIGGER IF EXISTS trg_social_chat_message_updated ON social_chat_message;
CREATE TRIGGER trg_social_chat_message_updated
BEFORE UPDATE ON social_chat_message
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
