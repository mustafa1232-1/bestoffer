BEGIN;

ALTER TABLE merchant
ADD COLUMN IF NOT EXISTS is_disabled BOOLEAN;

UPDATE merchant
SET is_disabled = FALSE
WHERE is_disabled IS NULL;

ALTER TABLE merchant
ALTER COLUMN is_disabled SET DEFAULT FALSE;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS customer_city VARCHAR(80);

UPDATE customer_order
SET customer_city = 'مدينة بسماية'
WHERE customer_city IS NULL OR TRIM(customer_city) = '';

ALTER TABLE customer_order
ALTER COLUMN customer_city SET DEFAULT 'مدينة بسماية';

CREATE TABLE IF NOT EXISTS customer_address (
  id               BIGSERIAL PRIMARY KEY,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  label            VARCHAR(80) NOT NULL,
  city             VARCHAR(80) NOT NULL DEFAULT 'مدينة بسماية',
  block            VARCHAR(20) NOT NULL,
  building_number  VARCHAR(20) NOT NULL,
  apartment        VARCHAR(20) NOT NULL,
  is_default       BOOLEAN NOT NULL DEFAULT FALSE,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION set_customer_address_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customer_address_updated ON customer_address;
CREATE TRIGGER trg_customer_address_updated
BEFORE UPDATE ON customer_address
FOR EACH ROW
EXECUTE FUNCTION set_customer_address_updated_at();

CREATE INDEX IF NOT EXISTS idx_customer_address_user_active
ON customer_address (customer_user_id, is_active, is_default, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_address_single_default
ON customer_address (customer_user_id)
WHERE is_default = TRUE AND is_active = TRUE;

INSERT INTO customer_address
  (customer_user_id, label, city, block, building_number, apartment, is_default, is_active)
SELECT
  u.id,
  'العنوان الأساسي',
  'مدينة بسماية',
  COALESCE(NULLIF(TRIM(u.block), ''), 'A'),
  COALESCE(NULLIF(TRIM(u.building_number), ''), '1'),
  COALESCE(NULLIF(TRIM(u.apartment), ''), '1'),
  TRUE,
  TRUE
FROM app_user u
WHERE NOT EXISTS (
  SELECT 1
  FROM customer_address a
  WHERE a.customer_user_id = u.id
    AND a.is_active = TRUE
);

COMMIT;
