-- Storefront contract fields for the marketplace redesign (§store-contract).
-- Additive & backward-compatible: every column is nullable or has a safe
-- default, so existing merchants keep working and no fabricated values are
-- introduced (missing = NULL, surfaced as "unknown" by the app, never faked).

BEGIN;

ALTER TABLE merchant ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS cover_image_url TEXT;
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS delivery_eta_min_minutes INT;
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS delivery_eta_max_minutes INT;
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(12,2);
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS minimum_order NUMERIC(12,2);
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE merchant ADD COLUMN IF NOT EXISTS next_open_at TIMESTAMPTZ;

-- Guard rails so the data can never express an impossible ETA/fee window.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'merchant_delivery_eta_range_check'
  ) THEN
    ALTER TABLE merchant ADD CONSTRAINT merchant_delivery_eta_range_check
      CHECK (
        (delivery_eta_min_minutes IS NULL OR delivery_eta_min_minutes >= 0)
        AND (delivery_eta_max_minutes IS NULL OR delivery_eta_max_minutes >= 0)
        AND (
          delivery_eta_min_minutes IS NULL
          OR delivery_eta_max_minutes IS NULL
          OR delivery_eta_max_minutes >= delivery_eta_min_minutes
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'merchant_delivery_fee_nonneg_check'
  ) THEN
    ALTER TABLE merchant ADD CONSTRAINT merchant_delivery_fee_nonneg_check
      CHECK (delivery_fee IS NULL OR delivery_fee >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'merchant_minimum_order_nonneg_check'
  ) THEN
    ALTER TABLE merchant ADD CONSTRAINT merchant_minimum_order_nonneg_check
      CHECK (minimum_order IS NULL OR minimum_order >= 0);
  END IF;
END $$;

COMMIT;
