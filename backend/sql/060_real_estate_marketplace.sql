BEGIN;

CREATE TABLE IF NOT EXISTS real_estate_listing (
  id BIGSERIAL PRIMARY KEY,
  owner_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  purpose VARCHAR(10) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'pending_admin_review',
  title VARCHAR(180) NOT NULL,
  description TEXT,
  area_sqm INT NOT NULL,
  bank_settlement_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  bank_settlement_mode VARCHAR(10) NOT NULL DEFAULT 'partial',
  furnished BOOLEAN NOT NULL DEFAULT FALSE,
  furnishing_description TEXT,
  phone VARCHAR(32) NOT NULL,
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  city VARCHAR(120),
  block VARCHAR(24),
  building_number VARCHAR(24),
  apartment_number VARCHAR(24),
  details_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  review_note TEXT,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  last_visible_status VARCHAR(40),
  hidden_due_subscription_expiry_at TIMESTAMPTZ,
  sold_at TIMESTAMPTZ,
  rented_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT real_estate_listing_purpose_check CHECK (purpose IN ('sale', 'rent')),
  CONSTRAINT real_estate_listing_status_check CHECK (
    status IN (
      'pending_admin_review',
      'active',
      'sold',
      'rented',
      'archived',
      'hidden_due_subscription_expiry'
    )
  ),
  CONSTRAINT real_estate_listing_area_check CHECK (area_sqm IN (100, 120, 140)),
  CONSTRAINT real_estate_listing_bank_mode_check CHECK (bank_settlement_mode IN ('partial', 'full')),
  CONSTRAINT real_estate_listing_price_check CHECK (price >= 0),
  CONSTRAINT real_estate_listing_bank_amount_check CHECK (bank_settlement_amount >= 0)
);

CREATE TABLE IF NOT EXISTS real_estate_listing_media (
  id BIGSERIAL PRIMARY KEY,
  listing_id BIGINT NOT NULL REFERENCES real_estate_listing(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS real_estate_listing_status_history (
  id BIGSERIAL PRIMARY KEY,
  listing_id BIGINT NOT NULL REFERENCES real_estate_listing(id) ON DELETE CASCADE,
  previous_status VARCHAR(40),
  next_status VARCHAR(40) NOT NULL,
  note TEXT,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_owner_recent
  ON real_estate_listing(owner_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_status_recent
  ON real_estate_listing(status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_purpose_status
  ON real_estate_listing(purpose, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_media_listing
  ON real_estate_listing_media(listing_id, sort_order ASC, id ASC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_status_history_listing
  ON real_estate_listing_status_history(listing_id, id DESC);

DROP TRIGGER IF EXISTS trg_real_estate_listing_updated ON real_estate_listing;
CREATE TRIGGER trg_real_estate_listing_updated
BEFORE UPDATE ON real_estate_listing
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
