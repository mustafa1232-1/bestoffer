-- Seed the `electronics_mobile` store activity into the database.
-- It has always existed in the application's built-in registry (so it already
-- worked at signup and in browsing), but it had no row in
-- store_activity_definition. Now that it is the adopted phones section
-- (phones_technology was merged into it in migration 188), make it a
-- first-class DB activity with sensible default product-category templates.

INSERT INTO store_activity_definition (
  activity_type,
  base_type,
  display_name_en,
  display_name_ar,
  has_discovery_subcategories,
  supports_chat,
  supports_attachments,
  supports_pharmacy_workflow,
  internal_category_mode,
  default_service_flags_json,
  default_badges_json,
  is_active
)
VALUES
  ('electronics_mobile', 'market', 'Electronics & Mobile', U&'\0625\0644\0643\062A\0631\0648\0646\064A\0627\062A \0648\0645\0648\0628\0627\064A\0644', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE)
ON CONFLICT (activity_type) DO UPDATE
SET
  base_type = EXCLUDED.base_type,
  display_name_en = EXCLUDED.display_name_en,
  display_name_ar = EXCLUDED.display_name_ar,
  has_discovery_subcategories = EXCLUDED.has_discovery_subcategories,
  internal_category_mode = EXCLUDED.internal_category_mode,
  is_active = TRUE,
  updated_at = NOW();

INSERT INTO store_activity_internal_category_template (
  activity_type,
  code,
  name_en,
  name_ar,
  icon,
  order_index,
  catalog_type,
  is_active,
  metadata_json
)
VALUES
  ('electronics_mobile', 'smartphones', 'Smartphones', U&'\0647\0648\0627\062A\0641 \0630\0643\064A\0629', 'smartphone', 10, 'electronics', TRUE, '{}'::jsonb),
  ('electronics_mobile', 'phone_accessories', 'Phone Accessories', U&'\0645\0644\062D\0642\0627\062A \0627\0644\0647\0648\0627\062A\0641', 'headphones', 20, 'electronics', TRUE, '{}'::jsonb),
  ('electronics_mobile', 'tablets_laptops', 'Tablets & Laptops', U&'\0623\062C\0647\0632\0629 \0644\0648\062D\064A\0629 \0648\062D\0648\0627\0633\064A\0628', 'laptop', 30, 'electronics', TRUE, '{}'::jsonb),
  ('electronics_mobile', 'chargers_cables', 'Chargers & Cables', U&'\0634\0648\0627\062D\0646 \0648\0643\0627\0628\0644\0627\062A', 'cable', 40, 'electronics', TRUE, '{}'::jsonb),
  ('electronics_mobile', 'home_electronics', 'Home Electronics', U&'\0623\062C\0647\0632\0629 \0625\0644\0643\062A\0631\0648\0646\064A\0629 \0645\0646\0632\0644\064A\0629', 'devices_other', 50, 'electronics', TRUE, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  icon = EXCLUDED.icon,
  order_index = EXCLUDED.order_index,
  catalog_type = EXCLUDED.catalog_type,
  is_active = TRUE,
  metadata_json = EXCLUDED.metadata_json,
  updated_at = NOW();
