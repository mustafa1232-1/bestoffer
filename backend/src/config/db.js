import pg from "pg";

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30_000,
});

export async function q(text, params) {
  return pool.query(text, params);
}

let ensureSchemaPromise = null;

export async function ensureSchema() {
  if (ensureSchemaPromise) return ensureSchemaPromise;

  ensureSchemaPromise = (async () => {
    await q(`
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

          IF NOT EXISTS (
            SELECT 1
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            WHERE t.typname = 'user_role'
              AND e.enumlabel = 'delivery'
          ) THEN
            ALTER TYPE user_role ADD VALUE 'delivery';
          END IF;

          IF NOT EXISTS (
            SELECT 1
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            WHERE t.typname = 'user_role'
              AND e.enumlabel = 'deputy_admin'
          ) THEN
            ALTER TYPE user_role ADD VALUE 'deputy_admin';
          END IF;

          IF NOT EXISTS (
            SELECT 1
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            WHERE t.typname = 'user_role'
              AND e.enumlabel = 'call_center'
          ) THEN
            ALTER TYPE user_role ADD VALUE 'call_center';
          END IF;
        END IF;
      END
      $$;
    `);

    await q(`
      ALTER TABLE merchant
      ADD COLUMN IF NOT EXISTS owner_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;
    `);

    await q(`
      ALTER TABLE app_user
      ADD COLUMN IF NOT EXISTS image_url TEXT;
    `);

    await q(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'merchant_owner_user_id_key'
        ) THEN
          ALTER TABLE merchant
          ADD CONSTRAINT merchant_owner_user_id_key UNIQUE (owner_user_id);
        END IF;
      END
      $$;
    `);

    await q(`
      ALTER TABLE merchant
      ADD COLUMN IF NOT EXISTS is_approved BOOLEAN;
    `);

    await q(`
      UPDATE merchant
      SET is_approved = TRUE
      WHERE is_approved IS NULL;
    `);

    await q(`
      ALTER TABLE merchant
      ALTER COLUMN is_approved SET DEFAULT FALSE;
    `);

    await q(`
      ALTER TABLE merchant
      ADD COLUMN IF NOT EXISTS is_disabled BOOLEAN;
    `);

    await q(`
      UPDATE merchant
      SET is_disabled = FALSE
      WHERE is_disabled IS NULL;
    `);

    await q(`
      ALTER TABLE merchant
      ALTER COLUMN is_disabled SET DEFAULT FALSE;
    `);

    await q(`
      ALTER TABLE merchant
      ADD COLUMN IF NOT EXISTS approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;
    `);

    await q(`
      ALTER TABLE merchant
      ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
    `);

    await q(`
      CREATE TABLE IF NOT EXISTS merchant_category (
        id          BIGSERIAL PRIMARY KEY,
        merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
        name        VARCHAR(120) NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (merchant_id, name)
      );
    `);

    await q(`
      CREATE OR REPLACE FUNCTION set_merchant_category_updated_at()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    `);

    await q(`
      DROP TRIGGER IF EXISTS trg_merchant_category_updated ON merchant_category;
    `);

    await q(`
      CREATE TRIGGER trg_merchant_category_updated
      BEFORE UPDATE ON merchant_category
      FOR EACH ROW
      EXECUTE FUNCTION set_merchant_category_updated_at();
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_merchant_category_merchant_sort
      ON merchant_category (merchant_id, sort_order, id);
    `);

    await q(`
      ALTER TABLE product
      ADD COLUMN IF NOT EXISTS category_id BIGINT REFERENCES merchant_category(id) ON DELETE SET NULL;
    `);

    await q(`
      ALTER TABLE product
      ADD COLUMN IF NOT EXISTS free_delivery BOOLEAN;
    `);

    await q(`
      UPDATE product
      SET free_delivery = FALSE
      WHERE free_delivery IS NULL;
    `);

    await q(`
      ALTER TABLE product
      ALTER COLUMN free_delivery SET DEFAULT FALSE;
    `);

    await q(`
      ALTER TABLE product
      ADD COLUMN IF NOT EXISTS offer_label VARCHAR(80);
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_product_merchant_category_available
      ON product (merchant_id, category_id, is_available);
    `);

    await q(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'settlement_status') THEN
          CREATE TYPE settlement_status AS ENUM ('pending', 'approved', 'rejected');
        END IF;
      END
      $$;
    `);

    await q(`
      CREATE TABLE IF NOT EXISTS merchant_settlement (
        id                   BIGSERIAL PRIMARY KEY,
        merchant_id          BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
        owner_user_id        BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        amount               NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
        cutoff_delivered_at  TIMESTAMPTZ,
        status               settlement_status NOT NULL DEFAULT 'pending',
        requested_note       TEXT,
        requested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        approved_by_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
        approved_at          TIMESTAMPTZ,
        admin_note           TEXT
      );
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS image_url TEXT;
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS preparing_started_at TIMESTAMPTZ;
    `);

    await q(`
      UPDATE customer_order
      SET approved_at = COALESCE(
            approved_at,
            preparing_started_at,
            prepared_at,
            picked_up_at,
            delivered_at,
            customer_confirmed_at,
            created_at
          )
      WHERE status <> 'pending'
        AND approved_at IS NULL;
    `);

    await q(`
      UPDATE customer_order
      SET preparing_started_at = COALESCE(
            preparing_started_at,
            approved_at,
            prepared_at
          )
      WHERE status IN ('preparing','ready_for_delivery','on_the_way','delivered')
        AND preparing_started_at IS NULL;
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS customer_city VARCHAR(80);
    `);

    await q(`
      UPDATE customer_order
      SET customer_city = 'مدينة بسماية'
      WHERE customer_city IS NULL OR TRIM(customer_city) = '';
    `);

    await q(`
      ALTER TABLE customer_order
      ALTER COLUMN customer_city SET DEFAULT 'مدينة بسماية';
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS merchant_rating SMALLINT;
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS merchant_review TEXT;
    `);

    await q(`
      ALTER TABLE customer_order
      ADD COLUMN IF NOT EXISTS merchant_rated_at TIMESTAMPTZ;
    `);

    await q(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'customer_order_merchant_rating_check'
        ) THEN
          ALTER TABLE customer_order
          ADD CONSTRAINT customer_order_merchant_rating_check
          CHECK (merchant_rating BETWEEN 1 AND 5);
        END IF;
      END
      $$;
    `);

    await q(`
      CREATE TABLE IF NOT EXISTS customer_favorite_product (
        customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        product_id       BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
        created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (customer_user_id, product_id)
      );
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_customer_favorite_product_customer
      ON customer_favorite_product (customer_user_id);
    `);

    await q(`
      CREATE TABLE IF NOT EXISTS app_notification (
        id          BIGSERIAL PRIMARY KEY,
        user_id     BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        order_id    BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
        merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
        type        VARCHAR(80) NOT NULL,
        title       VARCHAR(200) NOT NULL,
        body        TEXT,
        payload     JSONB,
        is_read     BOOLEAN NOT NULL DEFAULT FALSE,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        read_at     TIMESTAMPTZ
      );
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_app_notification_user_created
      ON app_notification (user_id, created_at DESC);
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_app_notification_user_unread
      ON app_notification (user_id, is_read);
    `);

    await q(`
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
    `);

    await q(`
      CREATE OR REPLACE FUNCTION set_customer_address_updated_at()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    `);

    await q(`
      DROP TRIGGER IF EXISTS trg_customer_address_updated ON customer_address;
    `);

    await q(`
      CREATE TRIGGER trg_customer_address_updated
      BEFORE UPDATE ON customer_address
      FOR EACH ROW
      EXECUTE FUNCTION set_customer_address_updated_at();
    `);

    await q(`
      CREATE INDEX IF NOT EXISTS idx_customer_address_user_active
      ON customer_address (customer_user_id, is_active, is_default, id DESC);
    `);

    await q(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_address_single_default
      ON customer_address (customer_user_id)
      WHERE is_default = TRUE AND is_active = TRUE;
    `);

    await q(`
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
    `);
  })();

  return ensureSchemaPromise;
}
