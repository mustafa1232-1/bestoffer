BEGIN;

ALTER TABLE coupon_redemption
  DROP CONSTRAINT IF EXISTS coupon_redemption_coupon_id_customer_id_key;

DROP INDEX IF EXISTS idx_coupon_redemption_unique;
DROP INDEX IF EXISTS uq_coupon_redemption_customer;

CREATE UNIQUE INDEX IF NOT EXISTS uq_coupon_redemption_active_customer
ON coupon_redemption(coupon_id, customer_id)
WHERE COALESCE(is_void, FALSE) = FALSE;

COMMIT;
