BEGIN;

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_kind_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_kind_chk
  CHECK (thread_kind IN ('private', 'business', 'group'));

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_distinct_users_check;

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_order_check;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_pair_shape_chk
  CHECK (
    (
      thread_kind IN ('private', 'business')
      AND user_a_id < user_b_id
    )
    OR (
      thread_kind = 'group'
      AND user_a_id > 0
      AND user_b_id > 0
    )
  );

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_context_shape_chk;
ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_context_shape_chk
  CHECK (
    (thread_kind = 'private' AND context_type = 'none' AND context_id = 0)
    OR
    (thread_kind = 'business' AND context_type <> 'none' AND context_id > 0)
    OR
    (thread_kind = 'group' AND context_type = 'none' AND context_id = 0)
  );

ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_unique_context;

DROP INDEX IF EXISTS idx_social_chat_thread_pair_context_unique;
CREATE UNIQUE INDEX idx_social_chat_thread_pair_context_unique
  ON social_chat_thread (user_a_id, user_b_id, thread_kind, context_type, context_id)
  WHERE thread_kind IN ('private', 'business');

CREATE TABLE IF NOT EXISTS social_chat_group (
  thread_id BIGINT PRIMARY KEY REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  owner_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  title VARCHAR(80) NOT NULL,
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_social_chat_group_updated ON social_chat_group;
CREATE TRIGGER trg_social_chat_group_updated
BEFORE UPDATE ON social_chat_group
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_chat_thread_member (
  thread_id BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  member_role TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  added_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  PRIMARY KEY (thread_id, user_id),
  CONSTRAINT social_chat_thread_member_role_chk
    CHECK (member_role IN ('owner', 'admin', 'member'))
);

CREATE INDEX IF NOT EXISTS idx_social_chat_thread_member_user_recent
  ON social_chat_thread_member (user_id, thread_id DESC);

INSERT INTO social_chat_thread_member (thread_id, user_id, member_role, added_by_user_id)
SELECT id, user_a_id, 'owner', user_a_id
FROM social_chat_thread
WHERE thread_kind IN ('private', 'business')
ON CONFLICT (thread_id, user_id) DO NOTHING;

INSERT INTO social_chat_thread_member (thread_id, user_id, member_role, added_by_user_id)
SELECT id, user_b_id, 'member', user_a_id
FROM social_chat_thread
WHERE thread_kind IN ('private', 'business')
  AND user_b_id <> user_a_id
ON CONFLICT (thread_id, user_id) DO NOTHING;

COMMIT;
