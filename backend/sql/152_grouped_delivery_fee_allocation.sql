BEGIN;

-- Multi-store grouped checkout pricing:
--   * customer_order.delivery_fee stays the allocated/charged fee
--   * customer_order.delivery_fee_raw stores the raw fee before group discount
--   * order_group.delivery_fee_total stays the allocated total
--   * order_group.raw_delivery_fee_total stores the pre-discount total
--   * order_group_item_summary.delivery_fee stays allocated
--   * order_group_item_summary.raw_delivery_fee stores raw
--
-- This is additive and non-destructive. Existing rows are backfilled so legacy
-- data continues to render with the same totals while the grouped checkout path
-- can now preserve both values explicitly.

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS delivery_fee_raw NUMERIC(12,2) NOT NULL DEFAULT 0;

ALTER TABLE order_group
  ADD COLUMN IF NOT EXISTS raw_delivery_fee_total NUMERIC(12,2) NOT NULL DEFAULT 0;

ALTER TABLE order_group_item_summary
  ADD COLUMN IF NOT EXISTS raw_delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0;

UPDATE customer_order
   SET delivery_fee_raw = COALESCE(delivery_fee, 0)
 WHERE delivery_fee_raw IS DISTINCT FROM COALESCE(delivery_fee, 0);

UPDATE order_group
   SET raw_delivery_fee_total = COALESCE(delivery_fee_total, 0)
 WHERE raw_delivery_fee_total IS DISTINCT FROM COALESCE(delivery_fee_total, 0);

UPDATE order_group_item_summary
   SET raw_delivery_fee = COALESCE(delivery_fee, 0)
 WHERE raw_delivery_fee IS DISTINCT FROM COALESCE(delivery_fee, 0);

COMMIT;
