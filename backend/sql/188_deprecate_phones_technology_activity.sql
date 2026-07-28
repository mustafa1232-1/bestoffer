-- Deprecate the redundant `phones_technology` store activity.
-- Its dedicated customer entry point was removed in favour of `electronics_mobile`
-- (the adopted phones section). To avoid leaving any store under an inactive
-- activity (which would make it unselectable/unresolvable), first reclassify
-- every existing `phones_technology` store to `electronics_mobile`, then
-- deactivate `phones_technology` so it is no longer offered at store signup.

UPDATE merchant
SET activity_type = 'electronics_mobile', updated_at = NOW()
WHERE activity_type = 'phones_technology';

UPDATE store_activity_definition
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'phones_technology';

UPDATE store_activity_internal_category_template
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'phones_technology';
