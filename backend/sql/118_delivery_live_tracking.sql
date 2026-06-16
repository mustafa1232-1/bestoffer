CREATE TABLE IF NOT EXISTS courier_presence (
  courier_user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  current_order_id BIGINT NULL REFERENCES customer_order(id) ON DELETE SET NULL,
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  heading_deg NUMERIC(6,2),
  speed_kmh NUMERIC(6,2),
  accuracy_m NUMERIC(6,2),
  is_online BOOLEAN NOT NULL DEFAULT TRUE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_courier_presence_order
  ON courier_presence (current_order_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_presence_updated
  ON courier_presence (updated_at DESC);

CREATE TABLE IF NOT EXISTS customer_order_share_token (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL UNIQUE REFERENCES customer_order(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  share_token TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NULL,
  revoked_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_order_share_token_active
  ON customer_order_share_token (share_token)
  WHERE revoked_at IS NULL;
