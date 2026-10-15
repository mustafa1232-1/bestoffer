CREATE TABLE IF NOT EXISTS service_emergency_location_updates (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  latitude NUMERIC(10, 7) NOT NULL,
  longitude NUMERIC(10, 7) NOT NULL,
  accuracy_meters NUMERIC(10, 2),
  speed_mps NUMERIC(10, 2),
  heading_degrees NUMERIC(7, 2),
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_emergency_location_request_time
  ON service_emergency_location_updates (request_id, captured_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS service_emergency_messages (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  sender_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  sender_role VARCHAR(32) NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_emergency_messages_request_time
  ON service_emergency_messages (request_id, created_at ASC, id ASC);
