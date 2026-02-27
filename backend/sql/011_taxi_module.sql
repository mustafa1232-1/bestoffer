BEGIN;

ALTER TABLE customer_address
ADD COLUMN IF NOT EXISTS latitude NUMERIC(9,6);

ALTER TABLE customer_address
ADD COLUMN IF NOT EXISTS longitude NUMERIC(9,6);

CREATE TABLE IF NOT EXISTS taxi_captain_presence (
  captain_user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  is_online       BOOLEAN NOT NULL DEFAULT FALSE,
  latitude        NUMERIC(9,6),
  longitude       NUMERIC(9,6),
  heading_deg     NUMERIC(5,2),
  speed_kmh       NUMERIC(6,2),
  accuracy_m      NUMERIC(6,2),
  last_seen_at    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (
      latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_presence_online
  ON taxi_captain_presence (is_online, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_profile (
  user_id            BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  profile_image_url  TEXT,
  car_image_url      TEXT,
  vehicle_type       VARCHAR(60) NOT NULL DEFAULT 'sedan',
  car_make           VARCHAR(80) NOT NULL,
  car_model          VARCHAR(80) NOT NULL,
  car_year           INTEGER NOT NULL CHECK (car_year BETWEEN 1980 AND 2035),
  car_color          VARCHAR(40),
  plate_number       VARCHAR(40) NOT NULL,
  is_active          BOOLEAN NOT NULL DEFAULT TRUE,
  rating_avg         NUMERIC(3,2) NOT NULL DEFAULT 0,
  rides_count        INTEGER NOT NULL DEFAULT 0,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_profile_active
  ON taxi_captain_profile (is_active, car_make, car_model);

CREATE TABLE IF NOT EXISTS taxi_ride_request (
  id                       BIGSERIAL PRIMARY KEY,
  customer_user_id         BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  assigned_captain_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  pickup_latitude          NUMERIC(9,6) NOT NULL,
  pickup_longitude         NUMERIC(9,6) NOT NULL,
  dropoff_latitude         NUMERIC(9,6) NOT NULL,
  dropoff_longitude        NUMERIC(9,6) NOT NULL,
  pickup_label             VARCHAR(240) NOT NULL,
  dropoff_label            VARCHAR(240) NOT NULL,
  proposed_fare_iqd        INTEGER NOT NULL CHECK (proposed_fare_iqd >= 0),
  agreed_fare_iqd          INTEGER CHECK (agreed_fare_iqd >= 0),
  search_radius_m          INTEGER NOT NULL DEFAULT 2000 CHECK (search_radius_m BETWEEN 500 AND 10000),
  note                     TEXT,
  status                   VARCHAR(32) NOT NULL DEFAULT 'searching',
  share_token              VARCHAR(80) UNIQUE,
  accepted_bid_id          BIGINT,
  expires_at               TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '3 minutes'),
  accepted_at              TIMESTAMPTZ,
  captain_arriving_at      TIMESTAMPTZ,
  started_at               TIMESTAMPTZ,
  completed_at             TIMESTAMPTZ,
  cancelled_at             TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (pickup_latitude BETWEEN -90 AND 90),
  CHECK (dropoff_latitude BETWEEN -90 AND 90),
  CHECK (pickup_longitude BETWEEN -180 AND 180),
  CHECK (dropoff_longitude BETWEEN -180 AND 180),
  CHECK (
    status IN (
      'searching',
      'captain_assigned',
      'captain_arriving',
      'ride_started',
      'completed',
      'cancelled',
      'expired'
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_customer
  ON taxi_ride_request (customer_user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_captain
  ON taxi_ride_request (assigned_captain_user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_status
  ON taxi_ride_request (status, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_ride_bid (
  id              BIGSERIAL PRIMARY KEY,
  ride_request_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  offered_fare_iqd INTEGER NOT NULL CHECK (offered_fare_iqd >= 0),
  eta_minutes     INTEGER CHECK (eta_minutes IS NULL OR eta_minutes BETWEEN 1 AND 180),
  note            TEXT,
  status          VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (status IN ('active', 'accepted', 'rejected', 'withdrawn', 'expired')),
  UNIQUE (ride_request_id, captain_user_id)
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_bid_request
  ON taxi_ride_bid (ride_request_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_bid_captain
  ON taxi_ride_bid (captain_user_id, status, created_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'taxi_ride_request_accepted_bid_fkey'
  ) THEN
    ALTER TABLE taxi_ride_request
      ADD CONSTRAINT taxi_ride_request_accepted_bid_fkey
      FOREIGN KEY (accepted_bid_id)
      REFERENCES taxi_ride_bid(id)
      ON DELETE SET NULL;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS taxi_ride_location_log (
  id               BIGSERIAL PRIMARY KEY,
  ride_request_id  BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  captain_user_id  BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  latitude         NUMERIC(9,6) NOT NULL,
  longitude        NUMERIC(9,6) NOT NULL,
  heading_deg      NUMERIC(5,2),
  speed_kmh        NUMERIC(6,2),
  accuracy_m       NUMERIC(6,2),
  source           VARCHAR(24) NOT NULL DEFAULT 'captain_app',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (latitude BETWEEN -90 AND 90),
  CHECK (longitude BETWEEN -180 AND 180)
);

CREATE INDEX IF NOT EXISTS idx_taxi_location_log_ride_time
  ON taxi_ride_location_log (ride_request_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_location_log_captain_time
  ON taxi_ride_location_log (captain_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_ride_event (
  id               BIGSERIAL PRIMARY KEY,
  ride_request_id  BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  actor_user_id    BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  event_type       VARCHAR(80) NOT NULL,
  message          TEXT,
  payload          JSONB,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_event_ride_time
  ON taxi_ride_event (ride_request_id, created_at DESC);

COMMIT;
