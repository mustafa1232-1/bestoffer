BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'deputy_admin'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'deputy_admin';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'call_center'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'call_center';
    END IF;
  END IF;
END
$$;

ALTER TABLE merchant
ADD COLUMN IF NOT EXISTS is_approved BOOLEAN;

UPDATE merchant
SET is_approved = TRUE
WHERE is_approved IS NULL;

ALTER TABLE merchant
ALTER COLUMN is_approved SET NOT NULL;

ALTER TABLE merchant
ALTER COLUMN is_approved SET DEFAULT FALSE;

ALTER TABLE merchant
ADD COLUMN IF NOT EXISTS approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE merchant
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_merchant_approval ON merchant (is_approved);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'settlement_status') THEN
    CREATE TYPE settlement_status AS ENUM ('pending', 'approved', 'rejected');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_settlement (
  id                   BIGSERIAL PRIMARY KEY,
  merchant_id          BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  owner_user_id        BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  amount               NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  cutoff_delivered_at  TIMESTAMPTZ,
  status               settlement_status NOT NULL DEFAULT 'pending',
  requested_note       TEXT,
  requested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_by_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at          TIMESTAMPTZ,
  admin_note           TEXT
);

CREATE INDEX IF NOT EXISTS idx_merchant_settlement_merchant_status
ON merchant_settlement (merchant_id, status);

CREATE INDEX IF NOT EXISTS idx_merchant_settlement_owner_status
ON merchant_settlement (owner_user_id, status);

COMMIT;
