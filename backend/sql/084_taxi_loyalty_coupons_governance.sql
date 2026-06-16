BEGIN;

-- ============================================================================
-- Taxi loyalty, coupons, captain governance, and admin reporting foundation.
-- This migration is additive and keeps existing taxi flows backward-compatible.
-- ============================================================================

CREATE TABLE IF NOT EXISTS taxi_saved_place (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  label VARCHAR(80) NOT NULL,
  place_type VARCHAR(16) NOT NULL DEFAULT 'custom'
    CHECK (place_type IN ('home', 'work', 'custom')),
  latitude NUMERIC(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  address_text VARCHAR(280) NOT NULL,
  note TEXT,
  icon_name VARCHAR(40),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_saved_place_user
ON taxi_saved_place(user_id, place_type, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_saved_place_single_home
ON taxi_saved_place(user_id)
WHERE place_type = 'home';

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_saved_place_single_work
ON taxi_saved_place(user_id)
WHERE place_type = 'work';

CREATE TABLE IF NOT EXISTS taxi_favorite_trip (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  label VARCHAR(120) NOT NULL,
  pickup_snapshot JSONB NOT NULL,
  dropoff_snapshot JSONB NOT NULL,
  icon_name VARCHAR(40),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_favorite_trip_user
ON taxi_favorite_trip(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_scheduled_ride (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  pickup_snapshot JSONB NOT NULL,
  dropoff_snapshot JSONB NOT NULL,
  proposed_fare_iqd INTEGER NOT NULL CHECK (proposed_fare_iqd >= 0),
  note TEXT,
  coupon_code VARCHAR(64),
  schedule_for TIMESTAMPTZ NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'pending_dispatch', 'assigned', 'cancelled', 'completed', 'expired')),
  dispatch_started_at TIMESTAMPTZ,
  dispatched_ride_request_id BIGINT REFERENCES taxi_ride_request(id) ON DELETE SET NULL,
  cancelled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_scheduled_ride_user_status
ON taxi_scheduled_ride(user_id, status, schedule_for ASC);

CREATE INDEX IF NOT EXISTS idx_taxi_scheduled_ride_dispatch
ON taxi_scheduled_ride(status, schedule_for ASC, id ASC);

CREATE TABLE IF NOT EXISTS taxi_coupon (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(64) NOT NULL UNIQUE,
  title VARCHAR(140) NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  valid_from TIMESTAMPTZ,
  valid_until TIMESTAMPTZ,
  max_total_uses INTEGER CHECK (max_total_uses IS NULL OR max_total_uses >= 1),
  max_uses_per_user SMALLINT NOT NULL DEFAULT 1 CHECK (max_uses_per_user BETWEEN 1 AND 3),
  apply_whole_app BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_admin_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_coupon_active_window
ON taxi_coupon(is_active, valid_from, valid_until, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_coupon_discount_tier (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  use_index SMALLINT NOT NULL CHECK (use_index BETWEEN 1 AND 3),
  discount_type VARCHAR(16) NOT NULL CHECK (discount_type IN ('percent', 'amount')),
  discount_value INTEGER NOT NULL CHECK (discount_value > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coupon_id, use_index)
);

CREATE TABLE IF NOT EXISTS taxi_coupon_target_user (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coupon_id, user_id)
);

CREATE TABLE IF NOT EXISTS taxi_coupon_target_building (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  building_code VARCHAR(24) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coupon_id, building_code)
);

CREATE TABLE IF NOT EXISTS taxi_coupon_target_block (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  block_code VARCHAR(24) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coupon_id, block_code)
);

CREATE TABLE IF NOT EXISTS taxi_coupon_target_compound (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  compound_code VARCHAR(24) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coupon_id, compound_code)
);

CREATE TABLE IF NOT EXISTS taxi_coupon_usage (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES taxi_coupon(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  ride_request_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  use_index SMALLINT NOT NULL CHECK (use_index BETWEEN 1 AND 3),
  discount_type VARCHAR(16) NOT NULL CHECK (discount_type IN ('percent', 'amount')),
  discount_value INTEGER NOT NULL CHECK (discount_value > 0),
  fare_before_discount_iqd INTEGER NOT NULL CHECK (fare_before_discount_iqd >= 0),
  discount_iqd INTEGER NOT NULL CHECK (discount_iqd >= 0),
  fare_after_discount_iqd INTEGER NOT NULL CHECK (fare_after_discount_iqd >= 0),
  status VARCHAR(16) NOT NULL DEFAULT 'settled'
    CHECK (status IN ('reserved', 'settled', 'cancelled')),
  reserved_at TIMESTAMPTZ,
  settled_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ride_request_id),
  UNIQUE (coupon_id, user_id, use_index)
);

CREATE INDEX IF NOT EXISTS idx_taxi_coupon_usage_coupon
ON taxi_coupon_usage(coupon_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_coupon_usage_user
ON taxi_coupon_usage(user_id, coupon_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_credit_ledger (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  ride_request_id BIGINT REFERENCES taxi_ride_request(id) ON DELETE SET NULL,
  entry_type VARCHAR(32) NOT NULL
    CHECK (entry_type IN (
      'coupon_discount',
      'admin_gift',
      'contest_reward',
      'manual_credit',
      'subscription_charge',
      'settlement_adjustment'
    )),
  amount_iqd INTEGER NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'settled', 'rejected', 'cancelled')),
  reference_kind VARCHAR(64),
  reference_id BIGINT,
  note TEXT,
  meta JSONB,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  settled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_credit_ledger_captain
ON taxi_captain_credit_ledger(captain_user_id, status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_captain_credit_ledger_reference
ON taxi_captain_credit_ledger(captain_user_id, entry_type, reference_kind, reference_id)
WHERE reference_kind IS NOT NULL AND reference_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS taxi_captain_subscription_cycle (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  cycle_month DATE NOT NULL,
  monthly_subscription_amount_iqd INTEGER NOT NULL CHECK (monthly_subscription_amount_iqd >= 0),
  approved_discounts_iqd INTEGER NOT NULL DEFAULT 0 CHECK (approved_discounts_iqd >= 0),
  approved_credits_iqd INTEGER NOT NULL DEFAULT 0 CHECK (approved_credits_iqd >= 0),
  payable_amount_iqd INTEGER NOT NULL DEFAULT 0 CHECK (payable_amount_iqd >= 0),
  carry_over_iqd INTEGER NOT NULL DEFAULT 0 CHECK (carry_over_iqd >= 0),
  carry_over_mode VARCHAR(24) NOT NULL DEFAULT 'rollover'
    CHECK (carry_over_mode IN ('zero_floor', 'rollover')),
  status VARCHAR(24) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'invoiced', 'paid', 'overdue', 'closed')),
  opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (captain_user_id, cycle_month)
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_subscription_cycle_status
ON taxi_captain_subscription_cycle(status, cycle_month DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_subscription_payment (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  cycle_id BIGINT REFERENCES taxi_captain_subscription_cycle(id) ON DELETE SET NULL,
  amount_iqd INTEGER NOT NULL CHECK (amount_iqd >= 0),
  payment_method VARCHAR(24) NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'bank_transfer', 'wallet', 'other')),
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  reference_no VARCHAR(140),
  note TEXT,
  paid_at TIMESTAMPTZ,
  approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_subscription_payment_captain
ON taxi_captain_subscription_payment(captain_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_contest (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(180) NOT NULL,
  description TEXT,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  target_type VARCHAR(40) NOT NULL
    CHECK (target_type IN ('trips_count', 'completed_rides', 'rating_avg', 'accepted_bids')),
  target_value NUMERIC(14,3) NOT NULL CHECK (target_value > 0),
  reward_type VARCHAR(40) NOT NULL
    CHECK (reward_type IN ('credit', 'cash_equivalent', 'subscription_discount', 'gift')),
  reward_value INTEGER NOT NULL CHECK (reward_value >= 0),
  eligibility_rules JSONB,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_admin_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_contest_active_window
ON taxi_captain_contest(is_active, start_at, end_at, id DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_contest_tier (
  id BIGSERIAL PRIMARY KEY,
  contest_id BIGINT NOT NULL REFERENCES taxi_captain_contest(id) ON DELETE CASCADE,
  target_value NUMERIC(14,3) NOT NULL CHECK (target_value > 0),
  reward_type VARCHAR(40) NOT NULL
    CHECK (reward_type IN ('credit', 'cash_equivalent', 'subscription_discount', 'gift')),
  reward_value INTEGER NOT NULL CHECK (reward_value >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (contest_id, target_value)
);

CREATE TABLE IF NOT EXISTS taxi_captain_contest_progress (
  id BIGSERIAL PRIMARY KEY,
  contest_id BIGINT NOT NULL REFERENCES taxi_captain_contest(id) ON DELETE CASCADE,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  progress_value NUMERIC(14,3) NOT NULL DEFAULT 0,
  is_qualified BOOLEAN NOT NULL DEFAULT FALSE,
  qualified_at TIMESTAMPTZ,
  last_calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (contest_id, captain_user_id)
);

CREATE TABLE IF NOT EXISTS taxi_captain_reward (
  id BIGSERIAL PRIMARY KEY,
  contest_id BIGINT REFERENCES taxi_captain_contest(id) ON DELETE SET NULL,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reward_type VARCHAR(40) NOT NULL
    CHECK (reward_type IN ('credit', 'cash_equivalent', 'subscription_discount', 'gift')),
  reward_value INTEGER NOT NULL CHECK (reward_value >= 0),
  source_type VARCHAR(24) NOT NULL DEFAULT 'contest'
    CHECK (source_type IN ('contest', 'gift', 'manual')),
  note TEXT,
  status VARCHAR(16) NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'settled', 'rejected', 'cancelled')),
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_reward_captain
ON taxi_captain_reward(captain_user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_rider_review_by_captain (
  id BIGSERIAL PRIMARY KEY,
  ride_request_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  rider_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  category VARCHAR(40),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ride_request_id, captain_user_id)
);

CREATE INDEX IF NOT EXISTS idx_taxi_rider_review_by_captain_rider
ON taxi_rider_review_by_captain(rider_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_complaint (
  id BIGSERIAL PRIMARY KEY,
  trip_id BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  captain_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  rider_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  category VARCHAR(40) NOT NULL,
  reason VARCHAR(240) NOT NULL,
  details TEXT,
  attachment_url TEXT,
  rating_at_time_of_complaint SMALLINT CHECK (rating_at_time_of_complaint BETWEEN 1 AND 5),
  status VARCHAR(24) NOT NULL DEFAULT 'new'
    CHECK (status IN ('new', 'under_review', 'resolved', 'rejected')),
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_complaint_status
ON taxi_captain_complaint(status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxi_captain_complaint_open_trip
ON taxi_captain_complaint(trip_id)
WHERE status IN ('new', 'under_review');

CREATE TABLE IF NOT EXISTS taxi_captain_warning (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  severity VARCHAR(16) NOT NULL DEFAULT 'low'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  reason_code VARCHAR(80),
  reason_text TEXT,
  affects_status BOOLEAN NOT NULL DEFAULT TRUE,
  status_effect VARCHAR(32)
    CHECK (status_effect IN ('warned', 'temporarily_suspended', 'under_review', 'banned')),
  admin_note TEXT,
  issued_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  revoked_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_warning_captain
ON taxi_captain_warning(captain_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS taxi_captain_status_history (
  id BIGSERIAL PRIMARY KEY,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  old_status VARCHAR(32),
  new_status VARCHAR(32) NOT NULL,
  reason_code VARCHAR(80),
  note TEXT,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxi_captain_status_history_captain
ON taxi_captain_status_history(captain_user_id, created_at DESC);

ALTER TABLE taxi_captain_profile
ADD COLUMN IF NOT EXISTS governance_status VARCHAR(32) NOT NULL DEFAULT 'active'
  CHECK (governance_status IN ('active', 'warned', 'temporarily_suspended', 'under_review', 'banned'));

ALTER TABLE taxi_captain_profile
ADD COLUMN IF NOT EXISTS warning_count INTEGER NOT NULL DEFAULT 0 CHECK (warning_count >= 0);

ALTER TABLE taxi_captain_profile
ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS schedule_mode VARCHAR(16) NOT NULL DEFAULT 'now'
  CHECK (schedule_mode IN ('now', 'scheduled'));

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS scheduled_ride_id BIGINT REFERENCES taxi_scheduled_ride(id) ON DELETE SET NULL;

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ;

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS coupon_id BIGINT REFERENCES taxi_coupon(id) ON DELETE SET NULL;

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS coupon_code_snapshot VARCHAR(64);

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS coupon_use_index SMALLINT CHECK (coupon_use_index BETWEEN 1 AND 3);

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS fare_before_discount_iqd INTEGER CHECK (fare_before_discount_iqd >= 0);

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS coupon_discount_iqd INTEGER NOT NULL DEFAULT 0 CHECK (coupon_discount_iqd >= 0);

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS fare_after_discount_iqd INTEGER CHECK (fare_after_discount_iqd >= 0);

ALTER TABLE taxi_ride_request
ADD COLUMN IF NOT EXISTS coupon_settlement_state VARCHAR(16) NOT NULL DEFAULT 'none'
  CHECK (coupon_settlement_state IN ('none', 'reserved', 'settled', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_schedule
ON taxi_ride_request(schedule_mode, scheduled_for, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_request_coupon
ON taxi_ride_request(coupon_id, coupon_settlement_state, completed_at DESC);

COMMIT;
