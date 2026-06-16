DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'taxi_captain'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'taxi_captain';
    END IF;
  END IF;
END
$$;

-- @SPLIT

BEGIN;

UPDATE app_user u
SET role = 'taxi_captain'
WHERE EXISTS (
  SELECT 1
  FROM taxi_captain_profile tcp
  WHERE tcp.user_id = u.id
)
  AND u.role = 'delivery';

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS rejected_captains_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS price_raise_prompted_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS final_acceptance_deadline_at TIMESTAMPTZ NULL;

UPDATE taxi_ride_request
SET final_acceptance_deadline_at = COALESCE(
  final_acceptance_deadline_at,
  COALESCE(created_at, NOW()) + INTERVAL '5 minutes'
)
WHERE final_acceptance_deadline_at IS NULL;

CREATE TABLE IF NOT EXISTS taxi_ride_decline (
  id BIGSERIAL PRIMARY KEY,
  ride_request_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ride_request_id, captain_user_id)
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_decline_ride_request
ON taxi_ride_decline(ride_request_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_decline_captain
ON taxi_ride_decline(captain_user_id, created_at DESC);

COMMIT;
