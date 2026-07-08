BEGIN;

-- Extend order status enum for richer lifecycle tracking (keeps legacy statuses intact)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'accepted_by_store';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'courier_requested';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'courier_assigned';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'picked_up';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'delivered_by_courier';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'received_by_customer';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'completed';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'cancelled_by_customer';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'cancelled_by_store';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'cancelled_by_admin';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'failed_delivery';
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'returned_if_needed';
  END IF;
END
$$;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS delivery_type VARCHAR(20) NOT NULL DEFAULT 'delivery',
  ADD COLUMN IF NOT EXISTS courier_source VARCHAR(20) NOT NULL DEFAULT 'app',
  ADD COLUMN IF NOT EXISTS courier_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS courier_assigned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ready_for_pickup_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS on_the_way_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
  ADD COLUMN IF NOT EXISTS failed_delivery_reason TEXT,
  ADD COLUMN IF NOT EXISTS returned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assigned_by_store BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'customer_order_delivery_type_check'
  ) THEN
    ALTER TABLE customer_order
      ADD CONSTRAINT customer_order_delivery_type_check
      CHECK (delivery_type IN ('delivery','pickup','merchant_delivery'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'customer_order_courier_source_check'
  ) THEN
    ALTER TABLE customer_order
      ADD CONSTRAINT customer_order_courier_source_check
      CHECK (courier_source IN ('app','merchant','none'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_customer_order_status_updated
ON customer_order(status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_courier_requested
ON customer_order(courier_requested_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_customer_order_completed_at
ON customer_order(completed_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS order_status_history (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  old_status order_status,
  new_status order_status,
  lifecycle_old VARCHAR(40),
  lifecycle_new VARCHAR(40),
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  changed_by_role VARCHAR(40),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order
ON order_status_history(order_id, created_at DESC);

CREATE TABLE IF NOT EXISTS courier_assignment (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  assignment_type VARCHAR(30) NOT NULL DEFAULT 'broadcast',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  response_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_courier_assignment_order
ON courier_assignment(order_id, status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_assignment_courier
ON courier_assignment(courier_user_id, status, requested_at DESC);

CREATE TABLE IF NOT EXISTS courier_profile (
  user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  is_app_courier BOOLEAN NOT NULL DEFAULT TRUE,
  is_merchant_courier BOOLEAN NOT NULL DEFAULT FALSE,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  vehicle_type VARCHAR(60),
  active_status BOOLEAN NOT NULL DEFAULT TRUE,
  availability_status VARCHAR(20) NOT NULL DEFAULT 'online',
  coverage_block VARCHAR(20),
  rating NUMERIC(4,2) NOT NULL DEFAULT 0,
  total_completed_orders INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_courier_profile_merchant
ON courier_profile(merchant_id, active_status);

CREATE INDEX IF NOT EXISTS idx_courier_profile_coverage
ON courier_profile(coverage_block, availability_status);

CREATE TABLE IF NOT EXISTS courier_daily_stats (
  id BIGSERIAL PRIMARY KEY,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL,
  total_orders INT NOT NULL DEFAULT 0,
  completed_orders INT NOT NULL DEFAULT 0,
  cancelled_orders INT NOT NULL DEFAULT 0,
  failed_orders INT NOT NULL DEFAULT 0,
  acceptance_rate NUMERIC(6,2) NOT NULL DEFAULT 0,
  cancellation_rate NUMERIC(6,2) NOT NULL DEFAULT 0,
  avg_pickup_minutes NUMERIC(8,2) NOT NULL DEFAULT 0,
  avg_delivery_minutes NUMERIC(8,2) NOT NULL DEFAULT 0,
  earnings_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(courier_user_id, stat_date)
);

CREATE TABLE IF NOT EXISTS courier_earning (
  id BIGSERIAL PRIMARY KEY,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  earning_type VARCHAR(30) NOT NULL DEFAULT 'delivery_fee',
  amount NUMERIC(12,2) NOT NULL,
  currency VARCHAR(6) NOT NULL DEFAULT 'IQD',
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_courier_earning_courier
ON courier_earning(courier_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS courier_competition (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(180) NOT NULL,
  description TEXT,
  competition_type VARCHAR(40) NOT NULL,
  target_value NUMERIC(12,2) NOT NULL,
  reward_amount NUMERIC(12,2) NOT NULL,
  reward_type VARCHAR(30) NOT NULL DEFAULT 'cash',
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  filters_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_courier_competition_active
ON courier_competition(is_active, start_at, end_at);

CREATE TABLE IF NOT EXISTS courier_competition_progress (
  id BIGSERIAL PRIMARY KEY,
  competition_id BIGINT NOT NULL REFERENCES courier_competition(id) ON DELETE CASCADE,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  current_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at TIMESTAMPTZ,
  reward_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  reward_paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(competition_id, courier_user_id)
);

CREATE INDEX IF NOT EXISTS idx_courier_competition_progress_courier
ON courier_competition_progress(courier_user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS merchant_billing_profile (
  merchant_id BIGINT PRIMARY KEY REFERENCES merchant(id) ON DELETE CASCADE,
  commission_rate NUMERIC(6,4) NOT NULL DEFAULT 0.10,
  commission_model VARCHAR(32) NOT NULL DEFAULT 'percentage',
  monthly_subscription_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  service_fee_mode VARCHAR(30) NOT NULL DEFAULT 'fixed',
  service_fee_value NUMERIC(12,2) NOT NULL DEFAULT 500,
  delivery_fee_mode VARCHAR(30) NOT NULL DEFAULT 'fixed',
  delivery_fee_value NUMERIC(12,2) NOT NULL DEFAULT 1000,
  app_delivery_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  merchant_delivery_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  settlement_cycle VARCHAR(20) NOT NULL DEFAULT 'weekly',
  distribution_policy VARCHAR(40) NOT NULL DEFAULT 'commission_service_delivery',
  grace_period_days INT NOT NULL DEFAULT 0,
  reminder_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_billing_profile_commission_model_check'
  ) THEN
    ALTER TABLE merchant_billing_profile
      ADD CONSTRAINT merchant_billing_profile_commission_model_check
      CHECK (commission_model IN ('percentage', 'monthly_subscription'));
  END IF;
END
$$;

INSERT INTO merchant_billing_profile(merchant_id)
SELECT m.id
FROM merchant m
WHERE NOT EXISTS (
  SELECT 1 FROM merchant_billing_profile mbp WHERE mbp.merchant_id = m.id
);

CREATE TABLE IF NOT EXISTS merchant_receivables_ledger (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  entry_type VARCHAR(30) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  direction VARCHAR(10) NOT NULL,
  balance_after NUMERIC(12,2),
  reference_type VARCHAR(50),
  reference_id BIGINT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_receivables_ledger_merchant
ON merchant_receivables_ledger(merchant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS merchant_payment_request (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  payment_scope VARCHAR(20) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  proof_file_url TEXT,
  note TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  review_note TEXT
);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_request_status
ON merchant_payment_request(status, submitted_at DESC);

CREATE TABLE IF NOT EXISTS merchant_payment_allocation (
  id BIGSERIAL PRIMARY KEY,
  payment_request_id BIGINT NOT NULL REFERENCES merchant_payment_request(id) ON DELETE CASCADE,
  allocated_to_type VARCHAR(30) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS merchant_daily_kpi (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  kpi_date DATE NOT NULL,
  orders_count INT NOT NULL DEFAULT 0,
  completed_orders INT NOT NULL DEFAULT 0,
  cancelled_orders INT NOT NULL DEFAULT 0,
  gross_sales NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_sales NUMERIC(12,2) NOT NULL DEFAULT 0,
  discounts_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  app_commission NUMERIC(12,2) NOT NULL DEFAULT 0,
  service_fee_due NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee_due NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(merchant_id, kpi_date)
);

CREATE TABLE IF NOT EXISTS merchant_product_sales_stats (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES product(id) ON DELETE SET NULL,
  stat_date DATE NOT NULL,
  qty_sold NUMERIC(12,2) NOT NULL DEFAULT 0,
  gross_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(merchant_id, product_id, stat_date)
);

CREATE TABLE IF NOT EXISTS merchant_category_sales_stats (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  category_id BIGINT REFERENCES merchant_category(id) ON DELETE SET NULL,
  stat_date DATE NOT NULL,
  qty_sold NUMERIC(12,2) NOT NULL DEFAULT 0,
  gross_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(merchant_id, category_id, stat_date)
);

COMMIT;
