BEGIN;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS address_id BIGINT REFERENCES customer_address(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_customer_order_address_id
ON customer_order (address_id);

COMMIT;
