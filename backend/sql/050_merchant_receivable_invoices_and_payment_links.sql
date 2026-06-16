BEGIN;

ALTER TABLE merchant_payment_request
  ADD COLUMN IF NOT EXISTS selection_mode VARCHAR(32),
  ADD COLUMN IF NOT EXISTS selection_meta_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS payment_method_other VARCHAR(120);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_payment_request_selection_mode_check'
  ) THEN
    ALTER TABLE merchant_payment_request
      ADD CONSTRAINT merchant_payment_request_selection_mode_check
      CHECK (
        selection_mode IS NULL OR
        selection_mode IN ('all_invoices', 'manual_selection', 'auto_match_amount')
      );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_receivable_invoice (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  invoice_number VARCHAR(80),
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  order_status VARCHAR(40),
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  service_fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  app_delivery_fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  store_delivery_fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  app_receivable_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  store_net_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  outstanding_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  invoice_status VARCHAR(24) NOT NULL DEFAULT 'unpaid',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(order_id)
);

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

CREATE TABLE IF NOT EXISTS merchant_payment_invoice_allocation (
  id BIGSERIAL PRIMARY KEY,
  payment_request_id BIGINT NOT NULL REFERENCES merchant_payment_request(id) ON DELETE CASCADE,
  receivable_invoice_id BIGINT NOT NULL REFERENCES merchant_receivable_invoice(id) ON DELETE CASCADE,
  allocated_amount NUMERIC(12,2) NOT NULL,
  allocation_order INTEGER NOT NULL DEFAULT 1,
  coverage_type VARCHAR(40) NOT NULL DEFAULT 'full',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(payment_request_id, receivable_invoice_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_payment_invoice_allocation_coverage_check'
  ) THEN
    ALTER TABLE merchant_payment_invoice_allocation
      ADD CONSTRAINT merchant_payment_invoice_allocation_coverage_check
      CHECK (coverage_type IN ('full', 'partial_existing_balance'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_payment_invoice_allocation_request
ON merchant_payment_invoice_allocation(payment_request_id, allocation_order ASC, id ASC);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_invoice_allocation_invoice
ON merchant_payment_invoice_allocation(receivable_invoice_id, created_at DESC);

COMMIT;
