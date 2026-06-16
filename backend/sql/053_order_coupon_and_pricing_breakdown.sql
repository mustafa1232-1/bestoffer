BEGIN;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS gross_subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS product_discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS coupon_id BIGINT REFERENCES coupon(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS coupon_code VARCHAR(80),
  ADD COLUMN IF NOT EXISTS coupon_discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pricing_breakdown_json JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE customer_order
SET gross_subtotal = COALESCE(NULLIF(gross_subtotal, 0), subtotal),
    product_discount_total = COALESCE(product_discount_total, 0),
    coupon_discount_total = COALESCE(coupon_discount_total, 0),
    pricing_breakdown_json = COALESCE(
      NULLIF(pricing_breakdown_json, '{}'::jsonb),
      jsonb_build_object(
        'grossSubtotal', COALESCE(NULLIF(gross_subtotal, 0), subtotal),
        'productDiscountTotal', COALESCE(product_discount_total, 0),
        'subtotalAfterProductDiscounts', subtotal,
        'couponDiscountTotal', COALESCE(coupon_discount_total, 0),
        'subtotalAfterAllDiscounts', GREATEST(subtotal - COALESCE(coupon_discount_total, 0), 0),
        'serviceFee', COALESCE(service_fee, 0),
        'deliveryFee', COALESCE(delivery_fee, 0),
        'totalAmount', COALESCE(total_amount, 0),
        'coupon', CASE
          WHEN coupon_id IS NULL AND NULLIF(TRIM(COALESCE(coupon_code, '')), '') IS NULL THEN NULL
          ELSE jsonb_build_object(
            'id', coupon_id,
            'code', NULLIF(TRIM(COALESCE(coupon_code, '')), ''),
            'discountAmount', COALESCE(coupon_discount_total, 0)
          )
        END
      )
    )
WHERE TRUE;

WITH redemption_map AS (
  SELECT
    cr.order_id,
    cr.coupon_id,
    c.code,
    cr.discount_amount
  FROM coupon_redemption cr
  JOIN coupon c ON c.id = cr.coupon_id
  WHERE cr.order_id IS NOT NULL
)
UPDATE customer_order o
SET coupon_id = COALESCE(o.coupon_id, rm.coupon_id),
    coupon_code = COALESCE(o.coupon_code, rm.code),
    coupon_discount_total = CASE
      WHEN COALESCE(o.coupon_discount_total, 0) > 0 THEN o.coupon_discount_total
      ELSE COALESCE(rm.discount_amount, 0)
    END
FROM redemption_map rm
WHERE rm.order_id = o.id;

ALTER TABLE order_item
  ADD COLUMN IF NOT EXISTS base_unit_price NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS line_discount_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pricing_breakdown_json JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE order_item
SET base_unit_price = COALESCE(base_unit_price, unit_price),
    line_discount_total = COALESCE(line_discount_total, 0),
    pricing_breakdown_json = COALESCE(
      NULLIF(pricing_breakdown_json, '{}'::jsonb),
      jsonb_build_object(
        'baseUnitPrice', COALESCE(base_unit_price, unit_price),
        'finalUnitPrice', unit_price,
        'quantity', quantity,
        'lineDiscountTotal', COALESCE(line_discount_total, 0),
        'grossLineTotal', COALESCE(base_unit_price, unit_price) * quantity,
        'lineTotal', line_total
      )
    )
WHERE TRUE;

ALTER TABLE order_item
  ALTER COLUMN base_unit_price SET DEFAULT 0;

UPDATE order_item
SET base_unit_price = unit_price
WHERE base_unit_price IS NULL;

ALTER TABLE order_item
  ALTER COLUMN base_unit_price SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customer_order_coupon_id
ON customer_order(coupon_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_coupon_code
ON customer_order(coupon_code);

COMMIT;
