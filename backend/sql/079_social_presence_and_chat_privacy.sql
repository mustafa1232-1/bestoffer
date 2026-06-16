ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS social_online_visibility TEXT NOT NULL DEFAULT 'connections',
  ADD COLUMN IF NOT EXISTS social_last_seen_visibility TEXT NOT NULL DEFAULT 'connections',
  ADD COLUMN IF NOT EXISTS social_read_receipts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS social_typing_indicators_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE app_user
  DROP CONSTRAINT IF EXISTS app_user_social_online_visibility_chk;
ALTER TABLE app_user
  ADD CONSTRAINT app_user_social_online_visibility_chk
  CHECK (social_online_visibility IN ('everyone', 'connections', 'nobody'));

ALTER TABLE app_user
  DROP CONSTRAINT IF EXISTS app_user_social_last_seen_visibility_chk;
ALTER TABLE app_user
  ADD CONSTRAINT app_user_social_last_seen_visibility_chk
  CHECK (social_last_seen_visibility IN ('everyone', 'connections', 'nobody'));

CREATE TABLE IF NOT EXISTS social_user_presence (
  user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_social_user_presence_heartbeat
  ON social_user_presence (heartbeat_at DESC);

INSERT INTO social_user_presence (user_id)
SELECT u.id
FROM app_user u
ON CONFLICT (user_id) DO NOTHING;
