-- Per-option special price (سعر خاص لكل مقاس/لون): an optional absolute price for
-- a single variant option (e.g. size "XL" = 30000). NULL means no special price
-- for that option. Applied on the product card when the option is selected; a
-- full-combination override (product_variant.price_override) still wins over it.
ALTER TABLE product_variant_option
  ADD COLUMN IF NOT EXISTS price_override NUMERIC(12,2);
