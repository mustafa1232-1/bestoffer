BEGIN;

CREATE TABLE IF NOT EXISTS social_scope_manager (
  id BIGSERIAL PRIMARY KEY,
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  manager_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  assigned_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (scope_type, scope_code, manager_user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_scope_manager_scope_created
  ON social_scope_manager (scope_type, scope_code, created_at DESC);

CREATE TABLE IF NOT EXISTS social_scope_announcement (
  id BIGSERIAL PRIMARY KEY,
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  title VARCHAR(180) NOT NULL,
  body TEXT NOT NULL,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_scope_announcement_scope_created
  ON social_scope_announcement (scope_type, scope_code, id DESC);

CREATE TABLE IF NOT EXISTS social_scope_chat_settings (
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  chat_locked BOOLEAN NOT NULL DEFAULT FALSE,
  locked_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (scope_type, scope_code)
);

DROP TRIGGER IF EXISTS trg_social_scope_chat_settings_updated
  ON social_scope_chat_settings;
CREATE TRIGGER trg_social_scope_chat_settings_updated
BEFORE UPDATE ON social_scope_chat_settings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_scope_chat_ban (
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  banned_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (scope_type, scope_code, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_scope_chat_ban_scope_created
  ON social_scope_chat_ban (scope_type, scope_code, created_at DESC);

CREATE TABLE IF NOT EXISTS social_scope_member_removal (
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  removed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (scope_type, scope_code, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_scope_member_removal_scope_created
  ON social_scope_member_removal (scope_type, scope_code, created_at DESC);

CREATE TABLE IF NOT EXISTS social_scope_chat_message (
  id BIGSERIAL PRIMARY KEY,
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  sender_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  body TEXT NOT NULL DEFAULT '',
  reply_to_message_id BIGINT REFERENCES social_scope_chat_message(id) ON DELETE SET NULL,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_social_scope_chat_message_updated
  ON social_scope_chat_message;
CREATE TRIGGER trg_social_scope_chat_message_updated
BEFORE UPDATE ON social_scope_chat_message
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_social_scope_chat_message_scope_recent
  ON social_scope_chat_message (scope_type, scope_code, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_scope_chat_message_sender_recent
  ON social_scope_chat_message (sender_user_id, id DESC);

CREATE TABLE IF NOT EXISTS social_scope_chat_message_reaction (
  message_id BIGINT NOT NULL REFERENCES social_scope_chat_message(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reaction VARCHAR(16) NOT NULL
    CHECK (reaction IN ('like', 'heart', 'laugh', 'fire')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_scope_chat_reaction_user_created
  ON social_scope_chat_message_reaction (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS social_scope_bill (
  id BIGSERIAL PRIMARY KEY,
  scope_type VARCHAR(16) NOT NULL
    CHECK (scope_type IN ('block', 'compound', 'building')),
  scope_code VARCHAR(40) NOT NULL,
  bill_category VARCHAR(40) NOT NULL,
  title VARCHAR(180) NOT NULL,
  amount NUMERIC(12,2),
  due_date DATE,
  details TEXT,
  apartment_code VARCHAR(40),
  attachment_url TEXT,
  attachment_kind VARCHAR(16)
    CHECK (
      attachment_kind IS NULL
      OR attachment_kind IN ('image', 'video', 'audio', 'file')
    ),
  attachment_name VARCHAR(180),
  issued_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_scope_bill_scope_recent
  ON social_scope_bill (scope_type, scope_code, id DESC);

COMMIT;
