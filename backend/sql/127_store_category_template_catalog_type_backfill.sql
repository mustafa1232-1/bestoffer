BEGIN;

WITH template_rows AS (
  SELECT
    c.id,
    CASE m.activity_type
      WHEN 'restaurant' THEN 'restaurant'
      WHEN 'sweets_bakery' THEN 'restaurant'
      WHEN 'coffee_drinks' THEN 'restaurant'
      WHEN 'fashion_clothing' THEN 'clothes'
      WHEN 'electronics_mobile' THEN 'electronics'
      WHEN 'electrical_lighting' THEN 'electronics'
      WHEN 'supermarket' THEN 'grocery'
      WHEN 'fruits_vegetables' THEN 'grocery'
      WHEN 'meat_poultry' THEN 'grocery'
      WHEN 'seafood' THEN 'grocery'
      WHEN 'home_kitchen' THEN 'furniture'
      ELSE NULL
    END AS target_catalog_type
  FROM merchant_category c
  JOIN merchant m ON m.id = c.merchant_id
  WHERE c.source = 'template'
    AND COALESCE(c.catalog_type, 'generic') = 'generic'
    AND m.activity_type IS NOT NULL
)
UPDATE merchant_category c
SET catalog_type = tr.target_catalog_type,
    updated_at = NOW()
FROM template_rows tr
WHERE c.id = tr.id
  AND tr.target_catalog_type IS NOT NULL;

COMMIT;
