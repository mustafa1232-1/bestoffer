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
  (
    'phone_maintenance',
    'market',
    'Phone Maintenance',
    U&'\0635\064A\0627\0646\0629 \0627\0644\0647\0648\0627\062A\0641',
    FALSE,
    FALSE,
    FALSE,
    FALSE,
    'merchant_defined_with_templates',
    '{}'::jsonb,
    '[]'::jsonb,
    TRUE
  ),
  (
    'phones_technology',
    'market',
    'Phones & Technology',
    U&'\0627\0644\0647\0648\0627\062A\0641 \0648\0627\0644\062A\0643\0646\0648\0644\0648\062C\064A\0627',
    FALSE,
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
  ('phone_maintenance', 'screen_repair', 'Screen Repair', U&'\0635\064A\0627\0646\0629 \0627\0644\0634\0627\0634\0627\062A', 'phone_android', 10, TRUE, '{}'::jsonb),
  ('phone_maintenance', 'battery_replacement', 'Battery Replacement', U&'\062A\0628\062F\064A\0644 \0627\0644\0628\0637\0627\0631\064A\0627\062A', 'battery_charging_full', 20, TRUE, '{}'::jsonb),
  ('phone_maintenance', 'software_services', 'Software Services', U&'\0628\0631\0645\062C\0629 \0648\0633\0648\0641\062A\0648\064A\0631', 'settings_applications', 30, TRUE, '{}'::jsonb),
  ('phone_maintenance', 'accessory_repair', 'Accessory Repair', U&'\0635\064A\0627\0646\0629 \0627\0644\0645\0644\062D\0642\0627\062A', 'build', 40, TRUE, '{}'::jsonb),
  ('phones_technology', 'smartphones', 'Smartphones', U&'\0647\0648\0627\062A\0641 \0630\0643\064A\0629', 'phone_android', 10, TRUE, '{}'::jsonb),
  ('phones_technology', 'phone_accessories', 'Phone Accessories', U&'\0645\0644\062D\0642\0627\062A \0627\0644\0647\0648\0627\062A\0641', 'headphones', 20, TRUE, '{}'::jsonb),
  ('phones_technology', 'tablets', 'Tablets', U&'\0623\062C\0647\0632\0629 \0644\0648\062D\064A\0629', 'tablet_mac', 30, TRUE, '{}'::jsonb),
  ('phones_technology', 'gadgets', 'Gadgets', U&'\0623\062C\0647\0632\0629 \062A\0642\0646\064A\0629', 'devices_other', 40, TRUE, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  icon = EXCLUDED.icon,
  order_index = EXCLUDED.order_index,
  is_active = TRUE,
  metadata_json = EXCLUDED.metadata_json,
  updated_at = NOW();
