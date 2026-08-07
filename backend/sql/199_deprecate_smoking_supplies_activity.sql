-- Deprecate the `smoking_supplies` store activity ("Tobacco & Hookah").
-- Its dedicated customer entry point (the "الدخان والأراكيل" hub card + 18+ gate)
-- was removed. To avoid leaving any store under an inactive activity (which would
-- make it unselectable/unresolvable), first normalise its categories to `generic`
-- so their products stay visible under a general market store, then reclassify
-- every existing `smoking_supplies` store to `market` (General Market / متجر عام),
-- and finally deactivate the activity so it is no longer offered at store signup.

-- 1) Normalise smoking/vape/hookah categories to generic for the affected stores
--    (do this BEFORE flipping the activity, while we can still target them).
UPDATE merchant_category mc
SET catalog_type = 'generic'
FROM merchant m
WHERE mc.merchant_id = m.id
  AND m.activity_type = 'smoking_supplies'
  AND mc.catalog_type IN ('smoking', 'vapes', 'hookah');

-- 2) Reclassify the stores themselves to the general market activity.
UPDATE merchant
SET activity_type = 'market', updated_at = NOW()
WHERE activity_type = 'smoking_supplies';

-- 3) Deactivate the activity definition and all of its seed rows so it is no
--    longer offered anywhere (store signup, discovery, internal templates).
UPDATE store_activity_definition
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'smoking_supplies';

UPDATE store_activity_discovery_option
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'smoking_supplies';

UPDATE store_activity_internal_category_template
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'smoking_supplies';
