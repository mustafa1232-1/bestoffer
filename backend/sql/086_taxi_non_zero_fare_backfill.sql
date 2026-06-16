BEGIN;

ALTER TABLE taxi_ride_bid
ADD COLUMN IF NOT EXISTS counter_offer_count SMALLINT NOT NULL DEFAULT 0;

ALTER TABLE taxi_ride_bid
ADD COLUMN IF NOT EXISTS last_offer_iqd INTEGER;

ALTER TABLE taxi_ride_bid
ADD COLUMN IF NOT EXISTS last_offer_by VARCHAR(16);

UPDATE taxi_ride_bid
SET
  last_offer_iqd = COALESCE(last_offer_iqd, offered_fare_iqd),
  last_offer_by = COALESCE(last_offer_by, 'captain')
WHERE last_offer_iqd IS NULL
   OR last_offer_by IS NULL;

ALTER TABLE taxi_ride_bid
DROP CONSTRAINT IF EXISTS chk_taxi_ride_bid_counter_offer_count;

ALTER TABLE taxi_ride_bid
ADD CONSTRAINT chk_taxi_ride_bid_counter_offer_count
CHECK (counter_offer_count BETWEEN 0 AND 6);

ALTER TABLE taxi_ride_bid
DROP CONSTRAINT IF EXISTS chk_taxi_ride_bid_last_offer_by;

ALTER TABLE taxi_ride_bid
ADD CONSTRAINT chk_taxi_ride_bid_last_offer_by
CHECK (last_offer_by IN ('captain', 'customer'));

-- Backfill active rides that were created with zero fare.
UPDATE taxi_ride_request
SET proposed_fare_iqd = 10000,
    fare_before_discount_iqd = CASE
      WHEN fare_before_discount_iqd IS NULL OR fare_before_discount_iqd <= 0 THEN 10000
      ELSE fare_before_discount_iqd
    END,
    fare_after_discount_iqd = CASE
      WHEN fare_after_discount_iqd IS NULL OR fare_after_discount_iqd < 0 THEN GREATEST(10000 - COALESCE(coupon_discount_iqd, 0), 0)
      ELSE fare_after_discount_iqd
    END,
    updated_at = NOW()
WHERE proposed_fare_iqd <= 0
  AND status IN ('searching', 'captain_assigned', 'captain_arriving', 'ride_started');

-- Backfill active bids that were created with zero fare.
UPDATE taxi_ride_bid
SET offered_fare_iqd = 10000,
    last_offer_iqd = 10000,
    updated_at = NOW()
WHERE offered_fare_iqd <= 0
  AND status = 'active';

-- Backfill scheduled rides waiting for dispatch with zero fare.
UPDATE taxi_scheduled_ride
SET proposed_fare_iqd = 10000,
    updated_at = NOW()
WHERE proposed_fare_iqd <= 0
  AND status IN ('scheduled', 'pending_dispatch');

COMMIT;
