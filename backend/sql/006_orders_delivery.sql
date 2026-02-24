BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'delivery'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'delivery';
    END IF;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    CREATE TYPE order_status AS ENUM (
      'pending',
      'preparing',
      'ready_for_delivery',
      'on_the_way',
      'delivered',
      'cancelled'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS customer_order (
  id                          BIGSERIAL PRIMARY KEY,
  merchant_id                 BIGINT NOT NULL REFERENCES merchant(id) ON DELETE RESTRICT,
  customer_user_id            BIGINT NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  delivery_user_id            BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  status                      order_status NOT NULL DEFAULT 'pending',
  customer_full_name          VARCHAR(120) NOT NULL,
  customer_phone              VARCHAR(20) NOT NULL,
  customer_block              VARCHAR(20) NOT NULL,
  customer_building_number    VARCHAR(20) NOT NULL,
  customer_apartment          VARCHAR(20) NOT NULL,
  note                        TEXT,
  subtotal                    NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee                NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount                NUMERIC(12,2) NOT NULL DEFAULT 0,
  estimated_prep_minutes      INTEGER,
  estimated_delivery_minutes  INTEGER,
  prepared_at                 TIMESTAMPTZ,
  picked_up_at                TIMESTAMPTZ,
  delivered_at                TIMESTAMPTZ,
  customer_confirmed_at       TIMESTAMPTZ,
  archived_by_delivery        BOOLEAN NOT NULL DEFAULT FALSE,
  archived_by_delivery_at     TIMESTAMPTZ,
  delivery_rating             SMALLINT CHECK (delivery_rating BETWEEN 1 AND 5),
  delivery_review             TEXT,
  rated_at                    TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_order_merchant_status
ON customer_order (merchant_id, status);

CREATE INDEX IF NOT EXISTS idx_customer_order_customer_status
ON customer_order (customer_user_id, status);

CREATE INDEX IF NOT EXISTS idx_customer_order_delivery_status
ON customer_order (delivery_user_id, status);

CREATE INDEX IF NOT EXISTS idx_customer_order_delivered_at
ON customer_order (delivered_at);

CREATE TABLE IF NOT EXISTS order_item (
  id            BIGSERIAL PRIMARY KEY,
  order_id       BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  product_id      BIGINT REFERENCES product(id) ON DELETE SET NULL,
  product_name    VARCHAR(150) NOT NULL,
  unit_price      NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  quantity        INTEGER NOT NULL CHECK (quantity > 0),
  line_total      NUMERIC(12,2) NOT NULL CHECK (line_total >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_item_order_id ON order_item (order_id);

CREATE TABLE IF NOT EXISTS delivery_day_archive (
  id               BIGSERIAL PRIMARY KEY,
  delivery_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  archive_date     DATE NOT NULL,
  orders_count     INTEGER NOT NULL DEFAULT 0,
  total_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (delivery_user_id, archive_date)
);

CREATE OR REPLACE FUNCTION set_customer_order_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customer_order_updated ON customer_order;
CREATE TRIGGER trg_customer_order_updated
BEFORE UPDATE ON customer_order
FOR EACH ROW
EXECUTE FUNCTION set_customer_order_updated_at();

COMMIT;
