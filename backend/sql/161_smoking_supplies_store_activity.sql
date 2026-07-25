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
VALUES (
  'smoking_supplies',
  'market',
  'Smoking Supplies',
  U&'\0645\0633\062A\0644\0632\0645\0627\062A \0627\0644\062A\062F\062E\064A\0646',
  TRUE,
  FALSE,
  FALSE,
  FALSE,
  'merchant_defined_with_templates',
  '{}'::jsonb,
  '[]'::jsonb,
  TRUE
)
ON CONFLICT (activity_type) DO UPDATE
SET
  base_type = EXCLUDED.base_type,
  display_name_en = EXCLUDED.display_name_en,
  display_name_ar = EXCLUDED.display_name_ar,
  has_discovery_subcategories = EXCLUDED.has_discovery_subcategories,
  supports_chat = EXCLUDED.supports_chat,
  supports_attachments = EXCLUDED.supports_attachments,
  supports_pharmacy_workflow = EXCLUDED.supports_pharmacy_workflow,
  internal_category_mode = EXCLUDED.internal_category_mode,
  default_service_flags_json = EXCLUDED.default_service_flags_json,
  default_badges_json = EXCLUDED.default_badges_json,
  is_active = TRUE,
  updated_at = NOW();

INSERT INTO store_activity_discovery_option (
  activity_type,
  code,
  label_en,
  label_ar,
  order_index,
  is_active,
  metadata_json
)
VALUES
  ('smoking_supplies', 'cigarettes', 'Cigarettes', U&'\0633\0643\0627\0626\0631', 10, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'hookahs_accessories', 'Hookahs & Accessories', U&'\0623\0631\0627\0643\064A\0644 \0648\0645\0644\062D\0642\0627\062A\0647\0627', 20, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'electronic_hookahs', 'Electronic Hookahs', U&'\0623\0631\0627\0643\064A\0644 \0625\0644\0643\062A\0631\0648\0646\064A\0629', 30, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'vapes', 'Vapes', U&'\0641\064A\0628\0627\062A', 40, TRUE, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  label_en = EXCLUDED.label_en,
  label_ar = EXCLUDED.label_ar,
  order_index = EXCLUDED.order_index,
  is_active = TRUE,
  metadata_json = EXCLUDED.metadata_json,
  updated_at = NOW();

INSERT INTO store_activity_internal_category_template (
  activity_type,
  code,
  name_en,
  name_ar,
  icon,
  order_index,
  is_active,
  metadata_json
)
VALUES
  ('smoking_supplies', 'cigarettes', 'Cigarettes', U&'\0633\0643\0627\0626\0631', 'smoking_rooms', 10, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'hookahs_accessories', 'Hookahs & Accessories', U&'\0623\0631\0627\0643\064A\0644 \0648\0645\0644\062D\0642\0627\062A\0647\0627', 'local_bar', 20, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'electronic_hookahs', 'Electronic Hookahs', U&'\0623\0631\0627\0643\064A\0644 \0625\0644\0643\062A\0631\0648\0646\064A\0629', 'electrical_services', 30, TRUE, '{}'::jsonb),
  ('smoking_supplies', 'vapes', 'Vapes', U&'\0641\064A\0628\0627\062A', 'vape_free', 40, TRUE, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  icon = EXCLUDED.icon,
  order_index = EXCLUDED.order_index,
  is_active = TRUE,
  metadata_json = EXCLUDED.metadata_json,
  updated_at = NOW();
