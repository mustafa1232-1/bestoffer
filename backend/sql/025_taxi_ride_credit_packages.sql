-- Taxi captain usage package: 10,000 IQD buys 15 completed rides.
-- Safe to run repeatedly; legacy date columns are intentionally preserved.
ALTER TABLE taxi_captain_subscription
  ADD COLUMN IF NOT EXISTS package_price_iqd INTEGER NOT NULL DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS package_ride_count SMALLINT NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS purchased_ride_credits INTEGER NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS consumed_ride_credits INTEGER NOT NULL DEFAULT 0;

ALTER TABLE taxi_captain_subscription
  DROP CONSTRAINT IF EXISTS chk_taxi_captain_credit_balance;
ALTER TABLE taxi_captain_subscription
  ADD CONSTRAINT chk_taxi_captain_credit_balance CHECK (
    package_price_iqd >= 0 AND package_ride_count > 0 AND
    purchased_ride_credits >= 0 AND consumed_ride_credits >= 0 AND
    consumed_ride_credits <= purchased_ride_credits
  );

ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS captain_credit_consumed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS taxi_captain_credit_transaction (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  delta INTEGER NOT NULL CHECK (delta <> 0),
  transaction_type VARCHAR(32) NOT NULL CHECK (transaction_type IN ('payment','completed_ride','admin_adjustment')),
  ride_request_id BIGINT REFERENCES taxi_ride_request(id) ON DELETE SET NULL,
  amount_iqd INTEGER CHECK (amount_iqd IS NULL OR amount_iqd >= 0),
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_credit_completed_ride
  ON taxi_captain_credit_transaction (ride_request_id)
  WHERE transaction_type = 'completed_ride';

CREATE INDEX IF NOT EXISTS idx_taxi_captain_subscription_remaining_credits
  ON taxi_captain_subscription
  ((purchased_ride_credits - consumed_ride_credits), cash_payment_pending);
