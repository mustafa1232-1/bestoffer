BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'owner'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'owner';
    END IF;
  END IF;
END
$$;

ALTER TABLE merchant
ADD COLUMN IF NOT EXISTS owner_user_id BIGINT UNIQUE REFERENCES app_user(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS merchant_category (
  id          BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  name        VARCHAR(120) NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (merchant_id, name)
);

CREATE TABLE IF NOT EXISTS product (
  id               BIGSERIAL PRIMARY KEY,
  merchant_id      BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  category_id      BIGINT REFERENCES merchant_category(id) ON DELETE SET NULL,
  name             VARCHAR(150) NOT NULL,
  description      TEXT,
  price            NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  discounted_price NUMERIC(12,2) CHECK (discounted_price >= 0),
  image_url        TEXT,
  free_delivery    BOOLEAN NOT NULL DEFAULT FALSE,
  offer_label      VARCHAR(80),
  is_available     BOOLEAN NOT NULL DEFAULT true,
  sort_order       INTEGER NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_category_merchant ON merchant_category(merchant_id);
CREATE INDEX IF NOT EXISTS idx_product_merchant ON product(merchant_id);
CREATE INDEX IF NOT EXISTS idx_product_merchant_available ON product(merchant_id, is_available);
CREATE INDEX IF NOT EXISTS idx_product_merchant_category_available ON product(merchant_id, category_id, is_available);

CREATE OR REPLACE FUNCTION set_product_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_product_updated ON product;
CREATE TRIGGER trg_product_updated
BEFORE UPDATE ON product
FOR EACH ROW
EXECUTE FUNCTION set_product_updated_at();

CREATE OR REPLACE FUNCTION set_merchant_category_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_merchant_category_updated ON merchant_category;
CREATE TRIGGER trg_merchant_category_updated
BEFORE UPDATE ON merchant_category
FOR EACH ROW
EXECUTE FUNCTION set_merchant_category_updated_at();

COMMIT;
