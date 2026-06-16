BEGIN;

CREATE INDEX IF NOT EXISTS idx_product_search_name_description
ON product
USING GIN (
  to_tsvector(
    'simple',
    COALESCE(name, '') || ' ' || COALESCE(description, '')
  )
);

CREATE INDEX IF NOT EXISTS idx_product_price_available
ON product (is_available, price, discounted_price, merchant_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_product_offer_sort
ON product (merchant_id, free_delivery, discounted_price, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_item_product
ON order_item (product_id, order_id);

CREATE INDEX IF NOT EXISTS idx_customer_order_merchant_delivery_stats
ON customer_order (merchant_id, status, delivered_at DESC, created_at DESC);

COMMIT;
