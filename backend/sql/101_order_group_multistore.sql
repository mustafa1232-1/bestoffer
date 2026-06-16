BEGIN;

CREATE TABLE IF NOT EXISTS order_group (
  id BIGSERIAL PRIMARY KEY,
  public_id VARCHAR(48) NOT NULL UNIQUE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status VARCHAR(40) NOT NULL DEFAULT 'pending',
  is_multi_store BOOLEAN NOT NULL DEFAULT FALSE,
  stores_count INTEGER NOT NULL DEFAULT 1 CHECK (stores_count > 0),
  gross_subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  product_discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  coupon_discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  service_fee_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  payment_method VARCHAR(32) NOT NULL DEFAULT 'cash_on_delivery',
  payment_status VARCHAR(32) NOT NULL DEFAULT 'pending_acceptance',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_group_customer_created
ON order_group (customer_user_id, created_at DESC);

CREATE OR REPLACE FUNCTION set_order_group_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_group_updated ON order_group;
CREATE TRIGGER trg_order_group_updated
BEFORE UPDATE ON order_group
FOR EACH ROW
EXECUTE FUNCTION set_order_group_updated_at();

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS order_group_id BIGINT REFERENCES order_group(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sub_order_id VARCHAR(64),
  ADD COLUMN IF NOT EXISTS order_scope VARCHAR(20) NOT NULL DEFAULT 'single',
  ADD COLUMN IF NOT EXISTS store_sequence SMALLINT NOT NULL DEFAULT 1;

ALTER TABLE customer_order
  DROP CONSTRAINT IF EXISTS customer_order_order_scope_chk;

ALTER TABLE customer_order
  ADD CONSTRAINT customer_order_order_scope_chk
  CHECK (order_scope IN ('single', 'group_child'));

CREATE INDEX IF NOT EXISTS idx_customer_order_group_id
ON customer_order (order_group_id, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_order_sub_order_id_unique
ON customer_order (sub_order_id)
WHERE sub_order_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS order_group_item_summary (
  id BIGSERIAL PRIMARY KEY,
  order_group_id BIGINT NOT NULL REFERENCES order_group(id) ON DELETE CASCADE,
  child_order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE RESTRICT,
  merchant_name VARCHAR(150) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'pending',
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (order_group_id, child_order_id)
);

CREATE INDEX IF NOT EXISTS idx_order_group_item_summary_group
ON order_group_item_summary (order_group_id, id ASC);

CREATE INDEX IF NOT EXISTS idx_order_group_item_summary_merchant
ON order_group_item_summary (merchant_id, created_at DESC);

CREATE OR REPLACE FUNCTION set_order_group_item_summary_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_group_item_summary_updated ON order_group_item_summary;
CREATE TRIGGER trg_order_group_item_summary_updated
BEFORE UPDATE ON order_group_item_summary
FOR EACH ROW
EXECUTE FUNCTION set_order_group_item_summary_updated_at();

COMMIT;
