BEGIN;

ALTER TABLE merchant_payment_request
  ADD COLUMN IF NOT EXISTS request_type VARCHAR(32) NOT NULL DEFAULT 'store_pays_app',
  ADD COLUMN IF NOT EXISTS requested_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_to_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_to_name VARCHAR(160),
  ADD COLUMN IF NOT EXISTS receiver_name VARCHAR(160),
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30),
  ADD COLUMN IF NOT EXISTS payment_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reference_code VARCHAR(120),
  ADD COLUMN IF NOT EXISTS internal_admin_note TEXT,
  ADD COLUMN IF NOT EXISTS issue_note TEXT,
  ADD COLUMN IF NOT EXISTS admin_payment_method VARCHAR(30),
  ADD COLUMN IF NOT EXISTS admin_reference_code VARCHAR(120),
  ADD COLUMN IF NOT EXISTS admin_payment_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS admin_payment_actor_name VARCHAR(160),
  ADD COLUMN IF NOT EXISTS final_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS final_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_locked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;

ALTER TABLE merchant_payment_request
  ALTER COLUMN status TYPE VARCHAR(40);

UPDATE merchant_payment_request
SET request_type = 'store_pays_app'
WHERE request_type IS NULL;

UPDATE merchant_payment_request
SET requested_amount = amount
WHERE requested_amount IS NULL;

UPDATE merchant_payment_request
SET paid_amount = CASE
  WHEN paid_amount IS NOT NULL THEN paid_amount
  WHEN status IN ('received', 'confirmed_by_admin', 'confirmed_received_by_store') THEN amount
  ELSE 0
END;

UPDATE merchant_payment_request
SET status = CASE
  WHEN status IN ('pending', 'review') THEN 'pending_admin_confirmation'
  WHEN status = 'received' THEN 'confirmed_by_admin'
  WHEN status = 'rejected' THEN 'rejected_by_admin'
  ELSE status
END
WHERE status IN ('pending', 'review', 'received', 'rejected');

UPDATE merchant_payment_request pr
SET created_by_user_id = m.owner_user_id
FROM merchant m
WHERE pr.merchant_id = m.id
  AND pr.created_by_user_id IS NULL;

UPDATE merchant_payment_request
SET is_locked = TRUE,
    locked_at = COALESCE(locked_at, reviewed_at)
WHERE status IN ('confirmed_by_admin', 'confirmed_received_by_store')
  AND is_locked = FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_payment_request_request_type_check'
  ) THEN
    ALTER TABLE merchant_payment_request
      ADD CONSTRAINT merchant_payment_request_request_type_check
      CHECK (
        request_type IN ('store_pays_app', 'app_pays_store')
      );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_payment_request_status_v3_check'
  ) THEN
    ALTER TABLE merchant_payment_request
      ADD CONSTRAINT merchant_payment_request_status_v3_check
      CHECK (
        status IN (
          'draft',
          'pending_admin_confirmation',
          'pending_admin_review',
          'approved_by_admin',
          'assigned_for_payment',
          'awaiting_store_confirmation',
          'confirmed_by_admin',
          'confirmed_received_by_store',
          'returned_for_revision',
          'issue_reported_by_store',
          'rejected_by_admin',
          'cancelled'
        )
      );
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_payment_request_type_status
ON merchant_payment_request(request_type, status, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_request_merchant_type
ON merchant_payment_request(merchant_id, request_type, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_request_locked
ON merchant_payment_request(is_locked, locked_at DESC);

CREATE TABLE IF NOT EXISTS merchant_payment_request_status_history (
  id BIGSERIAL PRIMARY KEY,
  payment_request_id BIGINT NOT NULL REFERENCES merchant_payment_request(id) ON DELETE CASCADE,
  old_status VARCHAR(40),
  new_status VARCHAR(40) NOT NULL,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  changed_by_role VARCHAR(24),
  note TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_request_status_history_request
ON merchant_payment_request_status_history(payment_request_id, created_at DESC);

CREATE TABLE IF NOT EXISTS merchant_app_payables_ledger (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  entry_type VARCHAR(40) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  direction VARCHAR(10) NOT NULL,
  balance_after NUMERIC(12,2),
  reference_type VARCHAR(50),
  reference_id BIGINT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_app_payables_ledger_direction_check'
  ) THEN
    ALTER TABLE merchant_app_payables_ledger
      ADD CONSTRAINT merchant_app_payables_ledger_direction_check
      CHECK (direction IN ('debit', 'credit'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_app_payables_ledger_merchant
ON merchant_app_payables_ledger(merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_app_payables_ledger_ref
ON merchant_app_payables_ledger(reference_type, reference_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_merchant_app_payables_auto_order_unique
ON merchant_app_payables_ledger(merchant_id, reference_id)
WHERE reference_type = 'order_auto_accrual'
  AND entry_type = 'order_share'
  AND direction = 'debit';

COMMIT;
