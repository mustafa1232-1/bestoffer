-- sql/002_users.sql
BEGIN;

-- Extensions (اختياري)
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS app_user (
  id              BIGSERIAL PRIMARY KEY,
  full_name       VARCHAR(120) NOT NULL,
  phone           VARCHAR(20)  NOT NULL UNIQUE,
  pin_hash        VARCHAR(120) NOT NULL,
  block           VARCHAR(20)  NOT NULL,
  building_number VARCHAR(20)  NOT NULL,
  apartment       VARCHAR(20)  NOT NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- تحديث updated_at تلقائيًا
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_app_user_updated ON app_user;
CREATE TRIGGER trg_app_user_updated
BEFORE UPDATE ON app_user
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- جلسات تسجيل الدخول (JWT refresh أو session token)
CREATE TABLE IF NOT EXISTS user_session (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  refresh_token VARCHAR(200) NOT NULL,
  user_agent    TEXT,
  ip            VARCHAR(64),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_session_user ON user_session(user_id);

COMMIT;