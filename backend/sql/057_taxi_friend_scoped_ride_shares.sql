CREATE TABLE IF NOT EXISTS taxi_ride_friend_share (
  id BIGSERIAL PRIMARY KEY,
  ride_request_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  friend_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
  shared_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ride_request_id, friend_user_id)
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_friend_share_friend_status
  ON taxi_ride_friend_share(friend_user_id, status, shared_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_friend_share_ride_status
  ON taxi_ride_friend_share(ride_request_id, status, shared_at DESC);
