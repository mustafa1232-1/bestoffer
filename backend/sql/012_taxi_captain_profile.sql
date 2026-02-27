BEGIN;

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

COMMIT;
