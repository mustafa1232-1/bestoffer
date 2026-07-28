-- Widen merchant_category.catalog_type to every catalog type the app taxonomy
-- knows about. The original CHECK (migration 123) only allowed the first six
-- types, so a category under a smoking / vape / hookah / supplements store
-- (all valid per the catalog taxonomy) failed to insert with a 500 error.

ALTER TABLE merchant_category
  DROP CONSTRAINT IF EXISTS merchant_category_catalog_type_chk;

ALTER TABLE merchant_category
  ADD CONSTRAINT merchant_category_catalog_type_chk
  CHECK (
    catalog_type IS NULL
    OR catalog_type IN (
      'generic', 'clothes', 'furniture', 'electronics', 'restaurant',
      'grocery', 'smoking', 'vapes', 'hookah', 'supplements'
    )
  );
