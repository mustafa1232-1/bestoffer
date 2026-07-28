-- Home Furniture department.
-- Adds two new store activities so a merchant can register directly under them
-- and customers can browse them in the dedicated "Home Furniture" hub. The
-- third sub-section (المفروشات) reuses the existing `furnishings` activity.
--   home_furniture  = أثاث منزلي        (Home Furniture)
--   kitchens_decor  = مطابخ وديكورات    (Kitchens & Decor)

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
  ('home_furniture', 'market', 'Home Furniture', U&'\0623\062B\0627\062B \0645\0646\0632\0644\064A', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('kitchens_decor', 'market', 'Kitchens & Decor', U&'\0645\0637\0627\0628\062E \0648\062F\064A\0643\0648\0631\0627\062A', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE)
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
  ('home_furniture', 'living_room', 'Living Room', U&'\0623\062B\0627\062B \063A\0631\0641\0629 \0627\0644\062C\0644\0648\0633', 'weekend', 10, 'furniture', TRUE, '{}'::jsonb),
  ('home_furniture', 'bedroom', 'Bedroom', U&'\063A\0631\0641 \0627\0644\0646\0648\0645', 'bed', 20, 'furniture', TRUE, '{}'::jsonb),
  ('home_furniture', 'dining', 'Dining Room', U&'\063A\0631\0641 \0627\0644\0637\0639\0627\0645', 'dining', 30, 'furniture', TRUE, '{}'::jsonb),
  ('home_furniture', 'home_office', 'Home Office', U&'\0623\062B\0627\062B \0645\0643\062A\0628\064A \0645\0646\0632\0644\064A', 'desk', 40, 'furniture', TRUE, '{}'::jsonb),
  ('home_furniture', 'wardrobes_storage', 'Wardrobes & Storage', U&'\062E\0632\0627\0626\0646 \0648\062A\062E\0632\064A\0646', 'door_sliding', 50, 'furniture', TRUE, '{}'::jsonb),
  ('kitchens_decor', 'kitchens', 'Kitchens', U&'\0645\0637\0627\0628\062E', 'kitchen', 10, 'furniture', TRUE, '{}'::jsonb),
  ('kitchens_decor', 'decor_accessories', 'Decor Accessories', U&'\0625\0643\0633\0633\0648\0627\0631\0627\062A \062F\064A\0643\0648\0631', 'category', 20, 'furniture', TRUE, '{}'::jsonb),
  ('kitchens_decor', 'lighting_decor', 'Lighting & Decor', U&'\0625\0646\0627\0631\0629 \0648\062F\064A\0643\0648\0631', 'light', 30, 'furniture', TRUE, '{}'::jsonb),
  ('kitchens_decor', 'wall_art_mirrors', 'Wall Art & Mirrors', U&'\0644\0648\062D\0627\062A \0648\0645\0631\0627\064A\0627', 'image', 40, 'furniture', TRUE, '{}'::jsonb)
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
