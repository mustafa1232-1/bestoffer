-- ============================================================
-- 025  Coupons / discount codes
-- ============================================================

CREATE TABLE IF NOT EXISTS coupon (
  id              SERIAL PRIMARY KEY,
  code            VARCHAR(50)  NOT NULL UNIQUE,
  description     TEXT,
  discount_type   VARCHAR(10)  NOT NULL CHECK (discount_type IN ('percent', 'fixed')),
  discount_value  NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),
  min_order_total NUMERIC(10,2) NOT NULL DEFAULT 0,
  max_uses        INT,                               -- NULL = unlimited
  uses_count      INT          NOT NULL DEFAULT 0,
  merchant_id     INT          REFERENCES merchant(id) ON DELETE CASCADE,  -- NULL = global
  valid_from      TIMESTAMPTZ,
  valid_until     TIMESTAMPTZ,
  is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
  created_by      INT          REFERENCES app_user(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupon_code      ON coupon(code);
CREATE INDEX IF NOT EXISTS idx_coupon_merchant  ON coupon(merchant_id);

-- Track which customer used which coupon on which order
CREATE TABLE IF NOT EXISTS coupon_redemption (
  id              SERIAL PRIMARY KEY,
  coupon_id       INT          NOT NULL REFERENCES coupon(id) ON DELETE CASCADE,
  customer_id     INT          NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  order_id        INT          REFERENCES customer_order(id) ON DELETE SET NULL,
  discount_amount NUMERIC(10,2) NOT NULL,
  redeemed_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coupon_redemption_unique
  ON coupon_redemption(coupon_id, customer_id);   -- one use per customer

CREATE INDEX IF NOT EXISTS idx_coupon_redemption_order ON coupon_redemption(order_id);
