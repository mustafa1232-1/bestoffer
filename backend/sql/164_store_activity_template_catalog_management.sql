ALTER TABLE store_activity_internal_category_template
  ADD COLUMN IF NOT EXISTS catalog_type VARCHAR(40) NOT NULL DEFAULT 'generic';

UPDATE store_activity_internal_category_template
SET catalog_type = CASE
  WHEN activity_type IN ('restaurant', 'sweets_bakery', 'coffee_drinks') THEN 'restaurant'
  WHEN activity_type = 'fashion_clothing' THEN 'clothes'
  WHEN activity_type IN ('electronics_mobile', 'phone_maintenance', 'phones_technology', 'electrical_lighting') THEN 'electronics'
  WHEN activity_type IN ('supermarket', 'fruits_vegetables', 'meat_poultry', 'seafood') THEN 'grocery'
  WHEN activity_type IN ('home_kitchen', 'furnishings') THEN 'furniture'
  WHEN activity_type = 'dietary_supplements' THEN 'supplements'
  WHEN activity_type = 'smoking_supplies' AND code = 'vapes' THEN 'vapes'
  WHEN activity_type = 'smoking_supplies' AND code IN ('hookahs_accessories', 'electronic_hookahs') THEN 'hookah'
  WHEN activity_type = 'smoking_supplies' THEN 'smoking'
  ELSE COALESCE(NULLIF(catalog_type, ''), 'generic')
END;

