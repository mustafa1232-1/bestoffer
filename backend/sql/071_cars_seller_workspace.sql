BEGIN;

CREATE TABLE IF NOT EXISTS car_listing (
  id BIGSERIAL PRIMARY KEY,
  owner_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status VARCHAR(40) NOT NULL DEFAULT 'active',
  title VARCHAR(180) NOT NULL,
  description TEXT,
  brand VARCHAR(120) NOT NULL,
  model VARCHAR(120) NOT NULL,
  model_year INT NOT NULL,
  condition VARCHAR(20) NOT NULL DEFAULT 'used',
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  mileage_km INT,
  city VARCHAR(120),
  phone VARCHAR(32) NOT NULL,
  transmission VARCHAR(20) NOT NULL DEFAULT 'automatic',
  fuel_type VARCHAR(20) NOT NULL DEFAULT 'fuel',
  body_type VARCHAR(20) NOT NULL DEFAULT 'sedan',
  color VARCHAR(60),
  last_visible_status VARCHAR(40),
  hidden_due_subscription_expiry_at TIMESTAMPTZ,
  sold_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT car_listing_status_check CHECK (
    status IN ('active', 'sold', 'archived', 'hidden_due_subscription_expiry')
  ),
  CONSTRAINT car_listing_condition_check CHECK (condition IN ('new', 'used')),
  CONSTRAINT car_listing_year_check CHECK (model_year BETWEEN 1980 AND 2035),
  CONSTRAINT car_listing_price_check CHECK (price >= 0),
  CONSTRAINT car_listing_mileage_check CHECK (mileage_km IS NULL OR mileage_km >= 0),
  CONSTRAINT car_listing_transmission_check CHECK (transmission IN ('automatic', 'manual')),
  CONSTRAINT car_listing_fuel_type_check CHECK (fuel_type IN ('fuel', 'hybrid', 'electric')),
  CONSTRAINT car_listing_body_type_check CHECK (
    body_type IN ('sedan', 'suv', 'crossover', 'hatchback', 'pickup', 'van')
  )
);

CREATE TABLE IF NOT EXISTS car_listing_media (
  id BIGSERIAL PRIMARY KEY,
  listing_id BIGINT NOT NULL REFERENCES car_listing(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_car_listing_owner_recent
  ON car_listing(owner_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_status_recent
  ON car_listing(status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_brand_model_status
  ON car_listing(brand, model, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_media_listing
  ON car_listing_media(listing_id, sort_order ASC, id ASC);

DROP TRIGGER IF EXISTS trg_car_listing_updated ON car_listing;
CREATE TRIGGER trg_car_listing_updated
BEFORE UPDATE ON car_listing
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
