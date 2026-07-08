BEGIN;

-- ============================================================
-- 129  Merchant monthly subscription invoices / debt lifecycle
-- ------------------------------------------------------------
-- Tracks the flat monthly subscription a merchant owes the app when
-- commission_model = 'monthly_subscription'. This debt is intentionally
-- SEPARATE from per-order cash settlement (delivery_cash_settlement /
-- merchant_cash_ledger_entry) and from per-order commission (which stays 0
-- for monthly_subscription merchants). Forward-only, additive, idempotent.
-- Table names follow the repo's singular convention (merchant_receivable_invoice,
-- merchant_cash_ledger_entry, merchant_payroll_batch, ...).
-- ============================================================

CREATE TABLE IF NOT EXISTS merchant_monthly_subscription_invoice (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  -- First day of the billing month (e.g. 2026-07-01). One invoice per month.
  billing_month DATE NOT NULL,
  subscription_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  remaining_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  -- Optional snapshot of the billing profile at generation time.
  billing_profile_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  due_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  notes TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Guarantee at most one invoice per merchant per billing month. Generation
-- relies on this via INSERT ... ON CONFLICT DO NOTHING so re-runs are safe.
CREATE UNIQUE INDEX IF NOT EXISTS uq_merchant_monthly_subscription_invoice_month
  ON merchant_monthly_subscription_invoice (merchant_id, billing_month);

CREATE INDEX IF NOT EXISTS idx_merchant_monthly_subscription_invoice_merchant
  ON merchant_monthly_subscription_invoice (merchant_id, billing_month DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_monthly_subscription_invoice_status
  ON merchant_monthly_subscription_invoice (status, due_at, id DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_monthly_subscription_invoice_status_check'
  ) THEN
    ALTER TABLE merchant_monthly_subscription_invoice
      ADD CONSTRAINT merchant_monthly_subscription_invoice_status_check
      CHECK (
        status IN (
          'pending',
          'partially_paid',
          'paid',
          'waived',
          'overdue'
        )
      );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_monthly_subscription_payment (
  id BIGSERIAL PRIMARY KEY,
  invoice_id BIGINT NOT NULL REFERENCES merchant_monthly_subscription_invoice(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  payment_method VARCHAR(30) NOT NULL DEFAULT 'cash',
  received_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_monthly_subscription_payment_invoice
  ON merchant_monthly_subscription_payment (invoice_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_monthly_subscription_payment_merchant
  ON merchant_monthly_subscription_payment (merchant_id, created_at DESC, id DESC);

COMMIT;
