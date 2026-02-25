BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_chat_role') THEN
    CREATE TYPE ai_chat_role AS ENUM ('user', 'assistant', 'system');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_draft_status') THEN
    CREATE TYPE ai_draft_status AS ENUM ('pending', 'confirmed', 'cancelled', 'expired');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS ai_chat_session (
  id               BIGSERIAL PRIMARY KEY,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  title            VARCHAR(120),
  last_message_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_chat_session_customer_last
ON ai_chat_session (customer_user_id, last_message_at DESC);

CREATE TABLE IF NOT EXISTS ai_chat_message (
  id          BIGSERIAL PRIMARY KEY,
  session_id  BIGINT NOT NULL REFERENCES ai_chat_session(id) ON DELETE CASCADE,
  role        ai_chat_role NOT NULL,
  text        TEXT NOT NULL,
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_chat_message_session_id
ON ai_chat_message (session_id, id);

CREATE TABLE IF NOT EXISTS ai_customer_profile (
  customer_user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  preference_json  JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_summary     TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_order_draft (
  id               BIGSERIAL PRIMARY KEY,
  token            VARCHAR(80) NOT NULL UNIQUE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  session_id       BIGINT REFERENCES ai_chat_session(id) ON DELETE SET NULL,
  merchant_id      BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  address_id       BIGINT REFERENCES customer_address(id) ON DELETE SET NULL,
  note             TEXT,
  items_json       JSONB NOT NULL,
  subtotal         NUMERIC(12,2) NOT NULL DEFAULT 0,
  service_fee      NUMERIC(12,2) NOT NULL DEFAULT 500,
  delivery_fee     NUMERIC(12,2) NOT NULL DEFAULT 1000,
  total_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  rationale        TEXT,
  status           ai_draft_status NOT NULL DEFAULT 'pending',
  linked_order_id  BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 minutes'),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_order_draft_customer_status
ON ai_order_draft (customer_user_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION set_ai_chat_session_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_chat_session_updated ON ai_chat_session;
CREATE TRIGGER trg_ai_chat_session_updated
BEFORE UPDATE ON ai_chat_session
FOR EACH ROW
EXECUTE FUNCTION set_ai_chat_session_updated_at();

CREATE OR REPLACE FUNCTION set_ai_customer_profile_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_customer_profile_updated ON ai_customer_profile;
CREATE TRIGGER trg_ai_customer_profile_updated
BEFORE UPDATE ON ai_customer_profile
FOR EACH ROW
EXECUTE FUNCTION set_ai_customer_profile_updated_at();

CREATE OR REPLACE FUNCTION set_ai_order_draft_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_order_draft_updated ON ai_order_draft;
CREATE TRIGGER trg_ai_order_draft_updated
BEFORE UPDATE ON ai_order_draft
FOR EACH ROW
EXECUTE FUNCTION set_ai_order_draft_updated_at();

COMMIT;
