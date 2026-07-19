BEGIN;

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS pricing_round SMALLINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS previous_proposed_fare_iqd INTEGER,
  ADD COLUMN IF NOT EXISTS price_raise_required_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS fare_version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE taxi_ride_decline
  ADD COLUMN IF NOT EXISTS pricing_round SMALLINT NOT NULL DEFAULT 1;

UPDATE taxi_ride_decline
SET pricing_round = COALESCE(pricing_round, 1);

ALTER TABLE taxi_ride_request
  DROP CONSTRAINT IF EXISTS taxi_ride_request_search_radius_m_check;

ALTER TABLE taxi_ride_request
  DROP CONSTRAINT IF EXISTS taxi_ride_request_status_check;

ALTER TABLE taxi_ride_request
  DROP CONSTRAINT IF EXISTS chk_taxi_ride_request_status;

ALTER TABLE taxi_ride_request
  DROP CONSTRAINT IF EXISTS chk_taxi_ride_request_search_radius_m;

UPDATE taxi_ride_request
SET pricing_round = COALESCE(pricing_round, 1),
    fare_version = COALESCE(fare_version, 1),
    search_radius_m = GREATEST(search_radius_m, 15000)
WHERE status = 'searching';

UPDATE taxi_ride_request r
SET rejected_captains_count = COALESCE((
  SELECT COUNT(*)::int
  FROM taxi_ride_decline d
  WHERE d.ride_request_id = r.id
    AND COALESCE(d.pricing_round, 1) = COALESCE(r.pricing_round, 1)
), 0)
WHERE r.status IN ('searching', 'price_raise_required');

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname
    INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'taxi_ride_request'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%status IN (%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE taxi_ride_request DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;

  SELECT conname
    INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'taxi_ride_request'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%search_radius_m BETWEEN%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE taxi_ride_request DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;
END
$$;

ALTER TABLE taxi_ride_request
  ADD CONSTRAINT chk_taxi_ride_request_status
  CHECK (
    status IN (
      'searching',
      'price_raise_required',
      'captain_assigned',
      'captain_arriving',
      'ride_started',
      'completed',
      'cancelled',
      'expired'
    )
  );

ALTER TABLE taxi_ride_request
  ADD CONSTRAINT chk_taxi_ride_request_search_radius_m
  CHECK (search_radius_m BETWEEN 500 AND 15000);

DELETE FROM taxi_ride_decline d
USING (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY ride_request_id, captain_user_id, pricing_round
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM taxi_ride_decline
) dup
WHERE d.id = dup.id
  AND dup.rn > 1;

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname
    INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'taxi_ride_decline'::regclass
    AND contype = 'u';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE taxi_ride_decline DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;
END
$$;

ALTER TABLE taxi_ride_decline
  ADD CONSTRAINT taxi_ride_decline_ride_request_captain_round_key
  UNIQUE (ride_request_id, captain_user_id, pricing_round);

COMMIT;
