BEGIN;

ALTER TABLE real_estate_listing
  ADD COLUMN IF NOT EXISTS rooms_count INT,
  ADD COLUMN IF NOT EXISTS bathrooms_count INT,
  ADD COLUMN IF NOT EXISTS floor_number INT,
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20) NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS view_count INT NOT NULL DEFAULT 0;

ALTER TABLE real_estate_listing
  ALTER COLUMN bank_settlement_mode SET DEFAULT 'none';

UPDATE real_estate_listing
SET bank_settlement_mode = 'none'
WHERE bank_settlement_mode IS NULL OR bank_settlement_mode = '';

ALTER TABLE real_estate_listing
  DROP CONSTRAINT IF EXISTS real_estate_listing_area_check;

ALTER TABLE real_estate_listing
  DROP CONSTRAINT IF EXISTS real_estate_listing_bank_mode_check;

ALTER TABLE real_estate_listing
  DROP CONSTRAINT IF EXISTS real_estate_listing_price_check;

ALTER TABLE real_estate_listing
  DROP CONSTRAINT IF EXISTS real_estate_listing_bank_amount_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_area_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_area_check CHECK (area_sqm > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_bank_mode_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_bank_mode_check
      CHECK (bank_settlement_mode IN ('none', 'partial', 'full'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_payment_method_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_payment_method_check
      CHECK (payment_method IN ('cash', 'installments', 'negotiable'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_price_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_price_check CHECK (price >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_bank_amount_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_bank_amount_check CHECK (bank_settlement_amount >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'real_estate_listing_view_count_check'
  ) THEN
    ALTER TABLE real_estate_listing
      ADD CONSTRAINT real_estate_listing_view_count_check CHECK (view_count >= 0);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS real_estate_saved_listing (
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  listing_id BIGINT NOT NULL REFERENCES real_estate_listing(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, listing_id)
);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_featured_status
  ON real_estate_listing(is_featured, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_city_block
  ON real_estate_listing(city, block, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_views
  ON real_estate_listing(view_count DESC, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_saved_listing_user_created
  ON real_estate_saved_listing(user_id, created_at DESC, listing_id DESC);

COMMIT;
