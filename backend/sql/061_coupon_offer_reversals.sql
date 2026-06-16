BEGIN;

ALTER TABLE coupon_redemption
  ADD COLUMN IF NOT EXISTS is_void BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS void_reason TEXT NULL;

ALTER TABLE merchant_offer_usage
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ NULL;

ALTER TABLE coupon_redemption
  DROP CONSTRAINT IF EXISTS coupon_redemption_coupon_id_customer_id_key;

DROP INDEX IF EXISTS uq_coupon_redemption_customer;

UPDATE coupon_redemption cr
SET is_void = TRUE,
    voided_at = COALESCE(cr.voided_at, NOW()),
    void_reason = COALESCE(cr.void_reason, 'order_cancelled_backfill')
FROM customer_order o
WHERE cr.order_id = o.id
  AND o.status IN (
    'cancelled',
    'cancelled_by_customer',
    'cancelled_by_store',
    'cancelled_by_admin'
  )
  AND COALESCE(cr.is_void, FALSE) = FALSE;

UPDATE merchant_offer_usage mou
SET is_void = TRUE,
    voided_at = COALESCE(mou.voided_at, NOW()),
    void_reason = COALESCE(mou.void_reason, 'order_cancelled_backfill')
FROM customer_order o
WHERE mou.order_id = o.id
  AND o.status IN (
    'cancelled',
    'cancelled_by_customer',
    'cancelled_by_store',
    'cancelled_by_admin'
  )
  AND COALESCE(mou.is_void, FALSE) = FALSE;

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

CREATE UNIQUE INDEX IF NOT EXISTS uq_coupon_redemption_active_customer
ON coupon_redemption(coupon_id, customer_id)
WHERE COALESCE(is_void, FALSE) = FALSE;

CREATE INDEX IF NOT EXISTS idx_coupon_redemption_order_id
ON coupon_redemption(order_id);

CREATE INDEX IF NOT EXISTS idx_coupon_redemption_active_coupon
ON coupon_redemption(coupon_id)
WHERE COALESCE(is_void, FALSE) = FALSE;

CREATE INDEX IF NOT EXISTS idx_merchant_offer_usage_order_id
ON merchant_offer_usage(order_id);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_usage_active_offer
ON merchant_offer_usage(offer_id)
WHERE COALESCE(is_void, FALSE) = FALSE;

COMMIT;
