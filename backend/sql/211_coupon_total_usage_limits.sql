BEGIN;

ALTER TABLE coupon_redemption
  ADD COLUMN IF NOT EXISTS is_void BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS void_reason TEXT NULL;

ALTER TABLE coupon_redemption
  DROP CONSTRAINT IF EXISTS coupon_redemption_coupon_id_customer_id_key;

DROP INDEX IF EXISTS idx_coupon_redemption_unique;
DROP INDEX IF EXISTS uq_coupon_redemption_customer;
DROP INDEX IF EXISTS uq_coupon_redemption_active_customer;

CREATE UNIQUE INDEX IF NOT EXISTS uq_coupon_redemption_active_order
ON coupon_redemption(coupon_id, order_id)
WHERE order_id IS NOT NULL
  AND COALESCE(is_void, FALSE) = FALSE;

ALTER TABLE coupon
  DROP CONSTRAINT IF EXISTS coupon_max_uses_positive;

ALTER TABLE coupon
  ADD CONSTRAINT coupon_max_uses_positive
  CHECK (max_uses IS NULL OR max_uses > 0);

ALTER TABLE coupon
  DROP CONSTRAINT IF EXISTS coupon_discount_value_range;

ALTER TABLE coupon
  ADD CONSTRAINT coupon_discount_value_range
  CHECK (
    (discount_type = 'percent' AND discount_value >= 0 AND discount_value <= 100)
    OR (discount_type = 'fixed' AND discount_value >= 0)
  );

ALTER TABLE coupon
  DROP CONSTRAINT IF EXISTS coupon_valid_date_range;

ALTER TABLE coupon
  ADD CONSTRAINT coupon_valid_date_range
  CHECK (valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from);

UPDATE coupon c
SET uses_count = COALESCE(src.active_count, 0)
FROM (
  SELECT coupon_id, COUNT(*)::int AS active_count
  FROM coupon_redemption
  WHERE COALESCE(is_void, FALSE) = FALSE
  GROUP BY coupon_id
) src
WHERE c.id = src.coupon_id;

UPDATE coupon c
SET uses_count = 0
WHERE NOT EXISTS (
  SELECT 1
  FROM coupon_redemption cr
  WHERE cr.coupon_id = c.id
    AND COALESCE(cr.is_void, FALSE) = FALSE
);

COMMIT;
