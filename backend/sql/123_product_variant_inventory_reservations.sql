-- Rich product authoring and transactional inventory reservations.

ALTER TABLE merchant_category
  ADD COLUMN IF NOT EXISTS catalog_type VARCHAR(24);

ALTER TABLE merchant_category
  DROP CONSTRAINT IF EXISTS merchant_category_catalog_type_chk;

ALTER TABLE merchant_category
  ADD CONSTRAINT merchant_category_catalog_type_chk
  CHECK (
    catalog_type IS NULL OR
    catalog_type IN ('generic', 'clothes', 'furniture', 'electronics', 'restaurant', 'grocery')
  );

UPDATE merchant_category
SET catalog_type = CASE
  WHEN lower(btrim(name)) IN ('cloths', 'clothes', 'clothing', 'fashion', 'ملابس', 'الملابس') THEN 'clothes'
  WHEN lower(btrim(name)) IN ('furniture', 'اثاث', 'أثاث', 'الاثاث', 'الأثاث') THEN 'furniture'
  WHEN lower(btrim(name)) IN ('electronics', 'electrical', 'الكترونيات', 'إلكترونيات', 'كهربائيات') THEN 'electronics'
  WHEN lower(btrim(name)) IN ('restaurant', 'restaurants', 'food', 'مطعم', 'مطاعم') THEN 'restaurant'
  WHEN lower(btrim(name)) IN ('grocery', 'groceries', 'supermarket', 'بقالة', 'مواد غذائية') THEN 'grocery'
  ELSE catalog_type
END
WHERE catalog_type IS NULL;

CREATE TABLE IF NOT EXISTS product_variant (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  signature VARCHAR(600) NOT NULL,
  selections_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  sku VARCHAR(120),
  barcode VARCHAR(120),
  material VARCHAR(160),
  price_override NUMERIC(12,2),
  discounted_price_override NUMERIC(12,2),
  stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  image_url TEXT,
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  unavailable_reason TEXT,
  unavailable_until TIMESTAMPTZ,
  sort_order INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(product_id, signature)
);

CREATE INDEX IF NOT EXISTS idx_product_variant_product_available
  ON product_variant(product_id, is_available, sort_order, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variant_sku
  ON product_variant(product_id, sku)
  WHERE sku IS NOT NULL AND btrim(sku) <> '';

CREATE TABLE IF NOT EXISTS inventory_reservation (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  order_item_id BIGINT NOT NULL REFERENCES order_item(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  variant_id BIGINT REFERENCES product_variant(id) ON DELETE SET NULL,
  variant_signature VARCHAR(600),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'consumed', 'completed', 'released', 'expired')),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(order_item_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_reservation_expiry
  ON inventory_reservation(status, expires_at, id);

CREATE INDEX IF NOT EXISTS idx_inventory_reservation_order
  ON inventory_reservation(order_id, status, id);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'expired';
  END IF;
END
$$;
