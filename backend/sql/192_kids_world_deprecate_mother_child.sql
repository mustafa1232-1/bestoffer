-- "Kids World" restructure.
-- The generic "Mother & Child" (mother_child) activity is replaced by the Kids
-- World hub, whose "everything a child needs" section maps to `kids_essentials`.
-- Reclassify any existing mother_child stores to kids_essentials, then deactivate
-- mother_child so it is no longer offered at store signup. The new kids
-- activities (kids_clothing, kids_toys, kids_essentials) are materialised by the
-- boot-time activity seed.

UPDATE merchant
SET activity_type = 'kids_essentials', updated_at = NOW()
WHERE activity_type = 'mother_child';

UPDATE store_activity_definition
SET is_active = FALSE, updated_at = NOW()
WHERE activity_type = 'mother_child';
