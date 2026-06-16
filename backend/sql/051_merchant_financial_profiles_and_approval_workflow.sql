BEGIN;

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS approval_status VARCHAR(40),
  ADD COLUMN IF NOT EXISTS financial_terms_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS financial_terms_sent_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS financial_terms_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS financial_terms_rejected_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS financial_terms_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS financial_terms_rejection_note TEXT;

UPDATE merchant
SET approval_status = CASE
  WHEN is_approved = TRUE THEN 'approved'
  ELSE 'pending_admin_review'
END
WHERE approval_status IS NULL;

ALTER TABLE merchant
  ALTER COLUMN approval_status SET DEFAULT 'pending_admin_review';

ALTER TABLE merchant
  ALTER COLUMN approval_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_approval_status_check'
  ) THEN
    ALTER TABLE merchant
      ADD CONSTRAINT merchant_approval_status_check
      CHECK (
        approval_status IN (
          'pending_admin_review',
          'awaiting_store_financial_acceptance',
          'approved',
          'rejected'
        )
      );
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_approval_status_v2
ON merchant(approval_status, is_disabled, created_at DESC, id DESC);

ALTER TABLE merchant_billing_profile
  ADD COLUMN IF NOT EXISTS commission_type VARCHAR(20),
  ADD COLUMN IF NOT EXISTS commission_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS service_fee_type VARCHAR(30),
  ADD COLUMN IF NOT EXISTS app_delivery_fee_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS store_delivery_fee_value NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS effective_from TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS profile_version BIGINT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_accepted_at TIMESTAMPTZ;

UPDATE merchant_billing_profile
SET commission_type = COALESCE(commission_type, 'percentage'),
    commission_value = COALESCE(
      commission_value,
      ROUND(COALESCE(commission_rate, 0) * 100.0, 2)
    ),
    service_fee_type = COALESCE(service_fee_type, COALESCE(service_fee_mode, 'fixed')),
    app_delivery_fee_value = COALESCE(app_delivery_fee_value, COALESCE(delivery_fee_value, 0)),
    store_delivery_fee_value = COALESCE(store_delivery_fee_value, 0),
    effective_from = COALESCE(effective_from, updated_at, NOW()),
    profile_version = COALESCE(profile_version, 1)
WHERE TRUE;

ALTER TABLE merchant_billing_profile
  ALTER COLUMN commission_type SET DEFAULT 'percentage',
  ALTER COLUMN commission_type SET NOT NULL,
  ALTER COLUMN commission_value SET DEFAULT 10,
  ALTER COLUMN commission_value SET NOT NULL,
  ALTER COLUMN service_fee_type SET DEFAULT 'fixed',
  ALTER COLUMN service_fee_type SET NOT NULL,
  ALTER COLUMN app_delivery_fee_value SET DEFAULT 0,
  ALTER COLUMN app_delivery_fee_value SET NOT NULL,
  ALTER COLUMN store_delivery_fee_value SET DEFAULT 0,
  ALTER COLUMN store_delivery_fee_value SET NOT NULL,
  ALTER COLUMN effective_from SET DEFAULT NOW(),
  ALTER COLUMN effective_from SET NOT NULL,
  ALTER COLUMN profile_version SET DEFAULT 1,
  ALTER COLUMN profile_version SET NOT NULL;

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
  ADD COLUMN IF NOT EXISTS service_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS financial_profile_version BIGINT,
  ADD COLUMN IF NOT EXISTS financial_config_snapshot_json JSONB;

CREATE INDEX IF NOT EXISTS idx_customer_order_financial_profile_version
ON customer_order(merchant_id, financial_profile_version);

COMMIT;
