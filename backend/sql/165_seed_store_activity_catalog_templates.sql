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
  ('smoking_supplies', 'market', 'Smoking Supplies', U&'\0645\0633\062A\0644\0632\0645\0627\062A \0627\0644\062A\062F\062E\064A\0646', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('furnishings', 'market', 'Furnishings', U&'\0627\0644\0645\0641\0631\0648\0634\0627\062A', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('dietary_supplements', 'market', 'Dietary Supplements', U&'\0627\0644\0645\0643\0645\0644\0627\062A \0627\0644\063A\0630\0627\0626\064A\0629', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('phone_maintenance', 'market', 'Phone Maintenance', U&'\0635\064A\0627\0646\0629 \0627\0644\0647\0648\0627\062A\0641', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('phones_technology', 'market', 'Phones & Technology', U&'\0627\0644\0647\0648\0627\062A\0641 \0648\0627\0644\062A\0643\0646\0648\0644\0648\062C\064A\0627', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE)
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
  ('smoking_supplies', 'cigarettes', 'Cigarettes', U&'\0633\0643\0627\0626\0631', 'smoking_rooms', 10, 'smoking', TRUE, '{}'::jsonb),
  ('smoking_supplies', 'hookahs_accessories', 'Hookahs & Accessories', U&'\0623\0631\0627\0643\064A\0644 \0648\0645\0644\062D\0642\0627\062A\0647\0627', 'local_bar', 20, 'hookah', TRUE, '{}'::jsonb),
  ('smoking_supplies', 'electronic_hookahs', 'Electronic Hookahs', U&'\0623\0631\0627\0643\064A\0644 \0625\0644\0643\062A\0631\0648\0646\064A\0629', 'electrical_services', 30, 'hookah', TRUE, '{}'::jsonb),
  ('smoking_supplies', 'vapes', 'Vapes', U&'\0641\064A\0628\0627\062A', 'vape_free', 40, 'vapes', TRUE, '{}'::jsonb),
  ('furnishings', 'sofas_seating', 'Sofas & Seating', U&'\0643\0646\0628 \0648\062C\0644\0633\0627\062A', 'chair', 10, 'furniture', TRUE, '{}'::jsonb),
  ('furnishings', 'beds_mattresses', 'Beds & Mattresses', U&'\0623\0633\0631\0629 \0648\0641\0631\0634\0627\062A', 'bed', 20, 'furniture', TRUE, '{}'::jsonb),
  ('furnishings', 'carpets_curtains', 'Carpets & Curtains', U&'\0633\062C\0627\062F \0648\0633\062A\0627\0626\0631', 'texture', 30, 'furniture', TRUE, '{}'::jsonb),
  ('furnishings', 'tables_storage', 'Tables & Storage', U&'\0637\0627\0648\0644\0627\062A \0648\062E\0632\0646', 'table_bar', 40, 'furniture', TRUE, '{}'::jsonb),
  ('dietary_supplements', 'vitamins', 'Vitamins', U&'\0641\064A\062A\0627\0645\064A\0646\0627\062A', 'spa', 10, 'supplements', TRUE, '{}'::jsonb),
  ('dietary_supplements', 'protein_fitness', 'Protein & Fitness', U&'\0628\0631\0648\062A\064A\0646 \0648\0644\064A\0627\0642\0629', 'fitness_center', 20, 'supplements', TRUE, '{}'::jsonb),
  ('dietary_supplements', 'minerals', 'Minerals', U&'\0645\0639\0627\062F\0646', 'medication', 30, 'supplements', TRUE, '{}'::jsonb),
  ('dietary_supplements', 'wellness', 'Wellness Supplements', U&'\0645\0643\0645\0644\0627\062A \0635\062D\064A\0629', 'health_and_safety', 40, 'supplements', TRUE, '{}'::jsonb),
  ('phone_maintenance', 'screen_repair', 'Screen Repair', U&'\0635\064A\0627\0646\0629 \0627\0644\0634\0627\0634\0627\062A', 'phone_android', 10, 'electronics', TRUE, '{}'::jsonb),
  ('phone_maintenance', 'battery_replacement', 'Battery Replacement', U&'\062A\0628\062F\064A\0644 \0627\0644\0628\0637\0627\0631\064A\0627\062A', 'battery_charging_full', 20, 'electronics', TRUE, '{}'::jsonb),
  ('phone_maintenance', 'software_services', 'Software Services', U&'\0628\0631\0645\062C\0629 \0648\0633\0648\0641\062A\0648\064A\0631', 'settings_applications', 30, 'electronics', TRUE, '{}'::jsonb),
  ('phone_maintenance', 'accessory_repair', 'Accessory Repair', U&'\0635\064A\0627\0646\0629 \0627\0644\0645\0644\062D\0642\0627\062A', 'build', 40, 'electronics', TRUE, '{}'::jsonb),
  ('phones_technology', 'smartphones', 'Smartphones', U&'\0647\0648\0627\062A\0641 \0630\0643\064A\0629', 'phone_android', 10, 'electronics', TRUE, '{}'::jsonb),
  ('phones_technology', 'phone_accessories', 'Phone Accessories', U&'\0645\0644\062D\0642\0627\062A \0627\0644\0647\0648\0627\062A\0641', 'headphones', 20, 'electronics', TRUE, '{}'::jsonb),
  ('phones_technology', 'tablets', 'Tablets', U&'\0623\062C\0647\0632\0629 \0644\0648\062D\064A\0629', 'tablet_mac', 30, 'electronics', TRUE, '{}'::jsonb),
  ('phones_technology', 'gadgets', 'Gadgets', U&'\0623\062C\0647\0632\0629 \062A\0642\0646\064A\0629', 'devices_other', 40, 'electronics', TRUE, '{}'::jsonb)
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
