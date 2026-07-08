BEGIN;

ALTER TABLE merchant_billing_profile
  ADD COLUMN IF NOT EXISTS commission_type VARCHAR(20),
  ADD COLUMN IF NOT EXISTS commission_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS commission_model VARCHAR(32),
  ADD COLUMN IF NOT EXISTS monthly_subscription_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS service_fee_type VARCHAR(30),
  ADD COLUMN IF NOT EXISTS app_delivery_fee_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS store_delivery_fee_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS effective_from TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS profile_version BIGINT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_accepted_at TIMESTAMPTZ;

UPDATE merchant_billing_profile
SET commission_type = COALESCE(commission_type, 'percentage'),
    commission_value = COALESCE(
      commission_value,
      ROUND(COALESCE(commission_rate, 0) * 100.0, 2)
    ),
    commission_model = COALESCE(
      commission_model,
      CASE
        WHEN COALESCE(monthly_subscription_amount, 0) > 0 THEN 'monthly_subscription'
        ELSE 'percentage'
      END
    ),
    monthly_subscription_amount = COALESCE(monthly_subscription_amount, 0),
    service_fee_type = COALESCE(service_fee_type, COALESCE(service_fee_mode, 'fixed')),
    app_delivery_fee_value = COALESCE(app_delivery_fee_value, COALESCE(delivery_fee_value, 0)),
    store_delivery_fee_value = COALESCE(store_delivery_fee_value, 0),
    effective_from = COALESCE(effective_from, updated_at, NOW()),
    profile_version = COALESCE(profile_version, 1),
    created_at = COALESCE(created_at, updated_at, NOW())
WHERE TRUE;

ALTER TABLE merchant_billing_profile
  ALTER COLUMN commission_type SET DEFAULT 'percentage',
  ALTER COLUMN commission_type SET NOT NULL,
  ALTER COLUMN commission_value SET DEFAULT 10,
  ALTER COLUMN commission_value SET NOT NULL,
  ALTER COLUMN commission_model SET DEFAULT 'percentage',
  ALTER COLUMN commission_model SET NOT NULL,
  ALTER COLUMN monthly_subscription_amount SET DEFAULT 0,
  ALTER COLUMN monthly_subscription_amount SET NOT NULL,
  ALTER COLUMN service_fee_type SET DEFAULT 'fixed',
  ALTER COLUMN service_fee_type SET NOT NULL,
  ALTER COLUMN app_delivery_fee_value SET DEFAULT 0,
  ALTER COLUMN app_delivery_fee_value SET NOT NULL,
  ALTER COLUMN store_delivery_fee_value SET DEFAULT 0,
  ALTER COLUMN store_delivery_fee_value SET NOT NULL,
  ALTER COLUMN effective_from SET DEFAULT NOW(),
  ALTER COLUMN effective_from SET NOT NULL,
  ALTER COLUMN profile_version SET DEFAULT 1,
  ALTER COLUMN profile_version SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT NOW(),
  ALTER COLUMN created_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_billing_profile_commission_type_check'
  ) THEN
    ALTER TABLE merchant_billing_profile
      ADD CONSTRAINT merchant_billing_profile_commission_type_check
      CHECK (commission_type IN ('percentage', 'fixed'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_billing_profile_commission_model_check'
  ) THEN
    ALTER TABLE merchant_billing_profile
      ADD CONSTRAINT merchant_billing_profile_commission_model_check
      CHECK (commission_model IN ('percentage', 'monthly_subscription'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_billing_profile_service_fee_type_check'
  ) THEN
    ALTER TABLE merchant_billing_profile
      ADD CONSTRAINT merchant_billing_profile_service_fee_type_check
      CHECK (service_fee_type IN ('fixed', 'percentage', 'per_order', 'global_rule'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_billing_profile_delivery_fee_mode_v2_check'
  ) THEN
    ALTER TABLE merchant_billing_profile
      ADD CONSTRAINT merchant_billing_profile_delivery_fee_mode_v2_check
      CHECK (delivery_fee_mode IN ('app_defined', 'store_defined', 'dynamic', 'fixed', 'percentage'));
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_billing_profile_audit (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  profile_version BIGINT NOT NULL,
  change_kind VARCHAR(40) NOT NULL DEFAULT 'admin_update',
  effective_from TIMESTAMPTZ NOT NULL,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  previous_profile_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  next_profile_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_billing_profile_audit_merchant
ON merchant_billing_profile_audit(merchant_id, profile_version DESC, created_at DESC);

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS service_fee NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS financial_profile_version BIGINT,
  ADD COLUMN IF NOT EXISTS financial_config_snapshot_json JSONB,
  ADD COLUMN IF NOT EXISTS store_net_received_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS app_due_from_delivery NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS store_cash_confirmed BOOLEAN,
  ADD COLUMN IF NOT EXISTS store_cash_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS store_cash_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS amount_received_actual NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_reason TEXT,
  ADD COLUMN IF NOT EXISTS settlement_status VARCHAR(40);

UPDATE customer_order
SET service_fee = COALESCE(service_fee, 0),
    store_net_received_amount = COALESCE(store_net_received_amount, 0),
    app_due_from_delivery = COALESCE(app_due_from_delivery, 0),
    store_cash_confirmed = COALESCE(store_cash_confirmed, FALSE),
    amount_received_actual = COALESCE(amount_received_actual, 0),
    difference_amount = COALESCE(difference_amount, 0),
    settlement_status = COALESCE(settlement_status, 'pending_store_confirmation')
WHERE service_fee IS NULL
   OR store_net_received_amount IS NULL
   OR app_due_from_delivery IS NULL
   OR store_cash_confirmed IS NULL
   OR amount_received_actual IS NULL
   OR difference_amount IS NULL
   OR settlement_status IS NULL;

ALTER TABLE customer_order
  ALTER COLUMN service_fee SET DEFAULT 0,
  ALTER COLUMN service_fee SET NOT NULL,
  ALTER COLUMN store_net_received_amount SET DEFAULT 0,
  ALTER COLUMN store_net_received_amount SET NOT NULL,
  ALTER COLUMN app_due_from_delivery SET DEFAULT 0,
  ALTER COLUMN app_due_from_delivery SET NOT NULL,
  ALTER COLUMN store_cash_confirmed SET DEFAULT FALSE,
  ALTER COLUMN store_cash_confirmed SET NOT NULL,
  ALTER COLUMN amount_received_actual SET DEFAULT 0,
  ALTER COLUMN amount_received_actual SET NOT NULL,
  ALTER COLUMN difference_amount SET DEFAULT 0,
  ALTER COLUMN difference_amount SET NOT NULL,
  ALTER COLUMN settlement_status SET DEFAULT 'pending_store_confirmation',
  ALTER COLUMN settlement_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'customer_order_settlement_status_check'
  ) THEN
    ALTER TABLE customer_order
      ADD CONSTRAINT customer_order_settlement_status_check
      CHECK (
        settlement_status IN (
          'pending_store_confirmation',
          'received',
          'difference_review',
          'closed',
          'cancelled'
        )
      );
  END IF;
END
$$;

ALTER TABLE delivery_cash_settlement
  ADD COLUMN IF NOT EXISTS store_net_received_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS app_due_from_delivery NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS store_cash_confirmed BOOLEAN,
  ADD COLUMN IF NOT EXISTS store_cash_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS store_cash_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS amount_received_actual NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_reason TEXT,
  ADD COLUMN IF NOT EXISTS settlement_status VARCHAR(40);

UPDATE delivery_cash_settlement
SET store_net_received_amount = COALESCE(store_net_received_amount, 0),
    app_due_from_delivery = COALESCE(app_due_from_delivery, 0),
    store_cash_confirmed = COALESCE(store_cash_confirmed, FALSE),
    amount_received_actual = COALESCE(amount_received_actual, 0),
    difference_amount = COALESCE(difference_amount, 0),
    settlement_status = COALESCE(settlement_status, 'pending_store_confirmation')
WHERE store_net_received_amount IS NULL
   OR app_due_from_delivery IS NULL
   OR store_cash_confirmed IS NULL
   OR amount_received_actual IS NULL
   OR difference_amount IS NULL
   OR settlement_status IS NULL;

ALTER TABLE delivery_cash_settlement
  ALTER COLUMN store_net_received_amount SET DEFAULT 0,
  ALTER COLUMN store_net_received_amount SET NOT NULL,
  ALTER COLUMN app_due_from_delivery SET DEFAULT 0,
  ALTER COLUMN app_due_from_delivery SET NOT NULL,
  ALTER COLUMN store_cash_confirmed SET DEFAULT FALSE,
  ALTER COLUMN store_cash_confirmed SET NOT NULL,
  ALTER COLUMN amount_received_actual SET DEFAULT 0,
  ALTER COLUMN amount_received_actual SET NOT NULL,
  ALTER COLUMN difference_amount SET DEFAULT 0,
  ALTER COLUMN difference_amount SET NOT NULL,
  ALTER COLUMN settlement_status SET DEFAULT 'pending_store_confirmation',
  ALTER COLUMN settlement_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'delivery_cash_settlement_status_check'
  ) THEN
    ALTER TABLE delivery_cash_settlement
      ADD CONSTRAINT delivery_cash_settlement_status_check
      CHECK (status IN ('pending', 'received', 'cancelled'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'delivery_cash_settlement_settlement_status_check'
  ) THEN
    ALTER TABLE delivery_cash_settlement
      ADD CONSTRAINT delivery_cash_settlement_settlement_status_check
      CHECK (
        settlement_status IN (
          'pending_store_confirmation',
          'received',
          'difference_review',
          'closed',
          'cancelled'
        )
      );
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_delivery_cash_settlement_merchant_pending
  ON delivery_cash_settlement (merchant_id, status, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_cash_settlement_delivery_pending
  ON delivery_cash_settlement (delivery_user_id, status, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_financial_profile_version
ON customer_order(merchant_id, financial_profile_version);

ALTER TABLE merchant_receivable_invoice
  ADD COLUMN IF NOT EXISTS store_net_received_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS app_due_from_delivery NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS difference_reason TEXT;

UPDATE merchant_receivable_invoice
SET store_net_received_amount = COALESCE(store_net_received_amount, store_net_amount),
    app_due_from_delivery = COALESCE(app_due_from_delivery, app_receivable_amount),
    difference_amount = COALESCE(difference_amount, 0)
WHERE store_net_received_amount IS NULL
   OR app_due_from_delivery IS NULL
   OR difference_amount IS NULL;

ALTER TABLE merchant_receivable_invoice
  ALTER COLUMN store_net_received_amount SET DEFAULT 0,
  ALTER COLUMN store_net_received_amount SET NOT NULL,
  ALTER COLUMN app_due_from_delivery SET DEFAULT 0,
  ALTER COLUMN app_due_from_delivery SET NOT NULL,
  ALTER COLUMN difference_amount SET DEFAULT 0,
  ALTER COLUMN difference_amount SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_receivable_invoice_status_check'
  ) THEN
    ALTER TABLE merchant_receivable_invoice
      ADD CONSTRAINT merchant_receivable_invoice_status_check
      CHECK (invoice_status IN ('unpaid', 'partially_paid', 'paid'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_receivable_invoice_merchant
ON merchant_receivable_invoice(merchant_id, issued_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_receivable_invoice_status
ON merchant_receivable_invoice(merchant_id, invoice_status, issued_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_cash_ledger_entry_merchant_created
  ON merchant_cash_ledger_entry (merchant_id, created_at DESC, id DESC);

COMMIT;
