BEGIN;

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS captain_rating SMALLINT
  CHECK (captain_rating BETWEEN 1 AND 5);

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS captain_review TEXT;

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS captain_rated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_captain_rating
  ON taxi_ride_request (assigned_captain_user_id, captain_rating, completed_at DESC);

COMMIT;
