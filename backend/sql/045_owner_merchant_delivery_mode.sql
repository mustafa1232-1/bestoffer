-- Owner can assign either platform delivery agent or restaurant-owned delivery.
-- This flag allows owner-side status updates for merchant-delivery workflow.

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS is_merchant_delivery BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_customer_order_merchant_delivery
  ON customer_order (is_merchant_delivery);
