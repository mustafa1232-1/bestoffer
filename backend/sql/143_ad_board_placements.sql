-- Ad board placements + category targeting + bilingual + analytics (marketplace
-- redesign §1). Additive & backward-compatible: existing ads default to
-- HOME_MAIN, so the current general home advertisement never breaks.

BEGIN;

ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS placement VARCHAR(32) NOT NULL DEFAULT 'HOME_MAIN';
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS activity_type VARCHAR(48);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS mobile_image_url TEXT;
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS title_ar VARCHAR(140);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS title_en VARCHAR(140);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS subtitle_ar VARCHAR(280);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS subtitle_en VARCHAR(280);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS cta_label_ar VARCHAR(60);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS cta_label_en VARCHAR(60);
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS impression_count BIGINT NOT NULL DEFAULT 0;
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS click_count BIGINT NOT NULL DEFAULT 0;
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS last_impression_at TIMESTAMPTZ;
ALTER TABLE app_ad_board_item ADD COLUMN IF NOT EXISTS last_click_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'app_ad_board_item_placement_check') THEN
    ALTER TABLE app_ad_board_item ADD CONSTRAINT app_ad_board_item_placement_check
      CHECK (placement IN ('HOME_MAIN', 'MARKETPLACE_HOME', 'MARKETPLACE_CATEGORY'));
  END IF;
END $$;

-- Fast active-by-placement lookup for the public marketplace read path.
CREATE INDEX IF NOT EXISTS idx_app_ad_board_item_placement
  ON app_ad_board_item (placement, is_active, priority, id DESC);

COMMIT;
