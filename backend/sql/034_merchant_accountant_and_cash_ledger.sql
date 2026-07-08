DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'accountant'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'accountant';
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_accountant (
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  accountant_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  source VARCHAR(20) NOT NULL DEFAULT 'owner',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (merchant_id, accountant_user_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_accountant_accountant
  ON merchant_accountant (accountant_user_id, is_active, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_accountant_merchant
  ON merchant_accountant (merchant_id, is_active, updated_at DESC);

CREATE TABLE IF NOT EXISTS delivery_cash_settlement (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  delivery_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  archive_date DATE NOT NULL,
  orders_count INTEGER NOT NULL DEFAULT 0 CHECK (orders_count >= 0),
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  store_net_received_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (store_net_received_amount >= 0),
  app_due_from_delivery NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (app_due_from_delivery >= 0),
  store_cash_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  store_cash_confirmed_at TIMESTAMPTZ,
  store_cash_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  amount_received_actual NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount_received_actual >= 0),
  difference_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  difference_reason TEXT,
  settlement_status VARCHAR(40) NOT NULL DEFAULT 'pending_store_confirmation',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  received_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (status IN ('pending', 'received', 'cancelled')),
  CHECK (settlement_status IN ('pending_store_confirmation', 'received', 'difference_review', 'closed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_delivery_cash_settlement_merchant_pending
  ON delivery_cash_settlement (merchant_id, status, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_cash_settlement_delivery_pending
  ON delivery_cash_settlement (delivery_user_id, status, requested_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS merchant_cash_ledger_entry (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  entry_type VARCHAR(32) NOT NULL,
  direction VARCHAR(10) NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  source_delivery_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  source_settlement_id BIGINT REFERENCES delivery_cash_settlement(id) ON DELETE SET NULL,
  source_archive_date DATE,
  note TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (direction IN ('credit', 'debit')),
  CHECK (entry_type IN ('opening_balance', 'delivery_settlement', 'expense'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_cash_ledger_entry_merchant_created
  ON merchant_cash_ledger_entry (merchant_id, created_at DESC, id DESC);
