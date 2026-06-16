BEGIN;

CREATE TABLE IF NOT EXISTS merchant_offer (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  title VARCHAR(160) NOT NULL,
  description VARCHAR(600),
  offer_type VARCHAR(32) NOT NULL CHECK (offer_type IN ('percentage', 'fixed_amount', 'buy_x_get_y')),
  discount_value NUMERIC(12,2),
  buy_quantity INT,
  get_quantity INT,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  status VARCHAR(24) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'active', 'disabled', 'expired')),
  max_usage INT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT merchant_offer_discount_rules CHECK (
    (offer_type = 'percentage' AND discount_value IS NOT NULL AND discount_value > 0 AND discount_value <= 100 AND buy_quantity IS NULL AND get_quantity IS NULL)
    OR (offer_type = 'fixed_amount' AND discount_value IS NOT NULL AND discount_value > 0 AND buy_quantity IS NULL AND get_quantity IS NULL)
    OR (offer_type = 'buy_x_get_y' AND discount_value IS NULL AND buy_quantity IS NOT NULL AND buy_quantity > 0 AND get_quantity IS NOT NULL AND get_quantity > 0)
  ),
  CONSTRAINT merchant_offer_usage_limit CHECK (max_usage IS NULL OR max_usage > 0),
  CONSTRAINT merchant_offer_dates CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at)
);

CREATE TABLE IF NOT EXISTS merchant_offer_product (
  offer_id BIGINT NOT NULL REFERENCES merchant_offer(id) ON DELETE CASCADE,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (offer_id, product_id)
);

CREATE TABLE IF NOT EXISTS merchant_offer_usage (
  id BIGSERIAL PRIMARY KEY,
  offer_id BIGINT NOT NULL REFERENCES merchant_offer(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  customer_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_void BOOLEAN NOT NULL DEFAULT FALSE,
  void_reason VARCHAR(120),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (offer_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_merchant_status
ON merchant_offer(merchant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_schedule
ON merchant_offer(merchant_id, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_product_product
ON merchant_offer_product(product_id, offer_id);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_usage_offer
ON merchant_offer_usage(offer_id, is_void, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_usage_order
ON merchant_offer_usage(order_id);

CREATE OR REPLACE FUNCTION set_merchant_offer_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_merchant_offer_updated_at ON merchant_offer;
CREATE TRIGGER trg_merchant_offer_updated_at
BEFORE UPDATE ON merchant_offer
FOR EACH ROW
EXECUTE FUNCTION set_merchant_offer_updated_at();

COMMIT;
