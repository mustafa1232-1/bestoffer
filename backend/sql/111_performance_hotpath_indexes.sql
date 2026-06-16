BEGIN;

CREATE INDEX IF NOT EXISTS idx_customer_order_customer_recent
ON customer_order (customer_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_merchant_status_recent
ON customer_order (merchant_id, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_delivery_status_recent
ON customer_order (delivery_user_id, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_group_recent
ON customer_order (order_group_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_order_item_order_product
ON order_item (order_id, product_id);

CREATE INDEX IF NOT EXISTS idx_product_merchant_available_recent
ON product (merchant_id, is_available, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_product_merchant_category_available
ON product (merchant_id, category_id, is_available, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_notification_user_unread_recent
ON app_notification (user_id, is_read, id DESC);

COMMIT;
