BEGIN;

ALTER TABLE product
  ADD COLUMN IF NOT EXISTS is_product_of_day BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS product_of_day_label VARCHAR(120),
  ADD COLUMN IF NOT EXISTS product_of_day_rank INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS product_of_day_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS highlight_priority INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_product_of_day_merchant
ON product (merchant_id, is_product_of_day, product_of_day_rank, updated_at DESC);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product'
      AND column_name = 'has_offer'
  )
  AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product'
      AND column_name = 'offer_price'
  ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_product_discount_highlight
             ON product (merchant_id, has_offer, offer_price, updated_at DESC)';
  END IF;
END
$$;

COMMIT;
