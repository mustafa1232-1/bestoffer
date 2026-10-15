BEGIN;

CREATE TABLE IF NOT EXISTS taxi_captain_ride_credit_ledger (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  ride_request_id BIGINT REFERENCES taxi_ride_request(id) ON DELETE SET NULL,
  entry_type VARCHAR(32) NOT NULL
    CHECK (entry_type IN ('top_up', 'ride_debit', 'admin_adjustment', 'migration_grant')),
  rides_delta INTEGER NOT NULL CHECK (rides_delta <> 0),
  amount_iqd INTEGER NOT NULL DEFAULT 0 CHECK (amount_iqd >= 0),
  payment_method VARCHAR(24),
  status VARCHAR(16) NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  reference_kind VARCHAR(64),
  reference_id BIGINT,
  note TEXT,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_ride_credit_captain
ON taxi_captain_ride_credit_ledger(captain_user_id, status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_captain_ride_credit_ride_debit
ON taxi_captain_ride_credit_ledger(captain_user_id, ride_request_id, entry_type)
WHERE entry_type = 'ride_debit' AND ride_request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_captain_ride_credit_reference
ON taxi_captain_ride_credit_ledger(captain_user_id, entry_type, reference_kind, reference_id)
WHERE reference_kind IS NOT NULL AND reference_id IS NOT NULL;

INSERT INTO taxi_captain_ride_credit_ledger (
  captain_user_id,
  entry_type,
  rides_delta,
  amount_iqd,
  status,
  note,
  meta,
  approved_at,
  created_at,
  updated_at
)
SELECT
  u.id,
  'migration_grant',
  30,
  0,
  'approved',
  'Initial ride-credit grant when taxi billing changed from monthly subscription to per-ride package.',
  jsonb_build_object('packageRides', 30, 'packageAmountIqd', 20000),
  NOW(),
  NOW(),
  NOW()
FROM app_user u
WHERE u.role = 'taxi_captain'
  AND COALESCE(u.taxi_account_approved, FALSE) = TRUE
  AND NOT EXISTS (
    SELECT 1
    FROM taxi_captain_ride_credit_ledger l
    WHERE l.captain_user_id = u.id
  );

COMMIT;
