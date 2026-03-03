BEGIN;

CREATE TABLE IF NOT EXISTS app_ad_board_item (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(140) NOT NULL,
  subtitle VARCHAR(280) NOT NULL,
  image_url TEXT,
  badge_label VARCHAR(40),
  cta_label VARCHAR(60),
  cta_target_type VARCHAR(24) NOT NULL DEFAULT 'none',
  cta_target_value TEXT,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  priority INTEGER NOT NULL DEFAULT 100,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT app_ad_board_item_cta_type_check
    CHECK (cta_target_type IN ('none', 'merchant', 'category', 'taxi', 'url')),
  CONSTRAINT app_ad_board_item_dates_check
    CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_active_window
  ON app_ad_board_item (is_active, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_priority
  ON app_ad_board_item (priority, id DESC);

CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_merchant
  ON app_ad_board_item (merchant_id);

DROP TRIGGER IF EXISTS trg_app_ad_board_item_updated ON app_ad_board_item;
CREATE TRIGGER trg_app_ad_board_item_updated
BEFORE UPDATE ON app_ad_board_item
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
