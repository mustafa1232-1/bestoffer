BEGIN;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS merchant_paid_actual NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS merchant_payment_receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS merchant_payment_without_receipt BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS merchant_payment_note TEXT,
  ADD COLUMN IF NOT EXISTS merchant_payment_recorded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS merchant_payment_recorded_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS customer_cash_received_actual NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS customer_cash_recorded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS purchase_difference_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS collection_difference_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_due_from_app NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reconciliation_review_status VARCHAR(32) NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reconciliation_review_note TEXT,
  ADD COLUMN IF NOT EXISTS reconciliation_reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reconciliation_reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'customer_order_reconciliation_review_status_check'
  ) THEN
    ALTER TABLE customer_order
      ADD CONSTRAINT customer_order_reconciliation_review_status_check
      CHECK (reconciliation_review_status IN ('pending', 'needs_review', 'approved', 'rejected'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'customer_order_merchant_payment_evidence_check'
  ) THEN
    ALTER TABLE customer_order
      ADD CONSTRAINT customer_order_merchant_payment_evidence_check
      CHECK (
        merchant_paid_actual IS NULL
        OR merchant_payment_receipt_url IS NOT NULL
        OR merchant_payment_without_receipt = TRUE
      );
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_customer_order_courier_reconciliation
  ON customer_order (delivery_user_id, reconciliation_review_status, delivered_at DESC, id DESC)
  WHERE merchant_paid_actual IS NOT NULL;

COMMIT;
