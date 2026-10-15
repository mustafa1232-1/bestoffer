BEGIN;

ALTER TABLE product
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_product_merchant_deleted
  ON product (merchant_id, deleted_at, id);

COMMIT;
