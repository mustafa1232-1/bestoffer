BEGIN;

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS latitude NUMERIC(9,6),
  ADD COLUMN IF NOT EXISTS longitude NUMERIC(9,6);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_latitude_range_check'
  ) THEN
    ALTER TABLE merchant
      ADD CONSTRAINT merchant_latitude_range_check
      CHECK (latitude IS NULL OR (latitude >= -90 AND latitude <= 90));
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_longitude_range_check'
  ) THEN
    ALTER TABLE merchant
      ADD CONSTRAINT merchant_longitude_range_check
      CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_merchant_geo_active_bbox
  ON merchant (latitude, longitude, id DESC)
  WHERE is_approved = TRUE
    AND COALESCE(is_disabled, FALSE) = FALSE
    AND latitude IS NOT NULL
    AND longitude IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_active_type_geo
  ON merchant (type, is_approved, is_disabled, latitude, longitude);

ALTER TABLE app_ad_board_item
  ADD COLUMN IF NOT EXISTS target_id BIGINT,
  ADD COLUMN IF NOT EXISTS target_route VARCHAR(240),
  ADD COLUMN IF NOT EXISTS promo_code VARCHAR(120),
  ADD COLUMN IF NOT EXISTS category VARCHAR(120),
  ADD COLUMN IF NOT EXISTS external_link TEXT;

ALTER TABLE app_ad_board_item
  DROP CONSTRAINT IF EXISTS app_ad_board_item_cta_type_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'app_ad_board_item_cta_type_check'
  ) THEN
    ALTER TABLE app_ad_board_item
      ADD CONSTRAINT app_ad_board_item_cta_type_check CHECK (
        cta_target_type IN (
          'none',
          'merchant',
          'category',
          'product',
          'taxi',
          'url',
          'internal_campaign_page',
          'store_ad',
          'promo_code',
          'category_ad',
          'external_link',
          'internal_route'
        )
      );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'app_ad_board_item_external_link_https_check'
  ) THEN
    ALTER TABLE app_ad_board_item
      ADD CONSTRAINT app_ad_board_item_external_link_https_check
      CHECK (external_link IS NULL OR external_link ~* '^https://');
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_priority_created
  ON app_ad_board_item (priority ASC, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_target_id
  ON app_ad_board_item (target_id);

COMMIT;
