BEGIN;

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
  ('restaurant', 'restaurant', 'Restaurant', 'مطعم', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('pharmacy', 'market', 'Pharmacy', 'صيدلية', TRUE, TRUE, TRUE, TRUE, 'merchant_defined_with_templates_and_constraints', '{"accepts_prescriptions": true, "supports_chat": true, "supports_attachments": true}'::jsonb, '["prescriptions","delivery"]'::jsonb, TRUE),
  ('supermarket', 'market', 'Supermarket', 'سوبرماركت', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('sweets_bakery', 'restaurant', 'Sweets & Bakery', 'حلويات ومخبوزات', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('coffee_drinks', 'restaurant', 'Coffee & Drinks', 'قهوة ومشروبات', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('meat_poultry', 'market', 'Meat & Poultry', 'ملحمة ودواجن', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('seafood', 'market', 'Seafood', 'أسماك ومأكولات بحرية', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('fruits_vegetables', 'market', 'Fruits & Vegetables', 'خضار وفواكه', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('construction', 'market', 'Construction & Tools', 'مواد إنشائية وعدة', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('electrical_lighting', 'market', 'Electrical & Lighting', 'كهربائيات وإنارة', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('electronics_mobile', 'market', 'Electronics & Mobile', 'إلكترونيات وموبايل', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('home_kitchen', 'market', 'Home & Kitchen', 'منزل ومطبخ', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('personal_care_beauty', 'market', 'Personal Care & Beauty', 'عناية شخصية وتجميل', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('flowers_gifts', 'market', 'Flowers & Gifts', 'زهور وهدايا', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('stationery_office', 'market', 'Stationery & Office', 'قرطاسية ومكتبية', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('mother_child', 'market', 'Mother & Child', 'أم وطفل', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('pet_supplies', 'market', 'Pet Supplies', 'مستلزمات حيوانات', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE),
  ('market', 'market', 'General Market', 'متجر عام', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb, TRUE)
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
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

INSERT INTO store_activity_discovery_option (
  activity_type,
  code,
  label_en,
  label_ar,
  order_index,
  metadata_json,
  is_active
)
VALUES
  ('restaurant', 'eastern', 'Eastern', 'شرقي', 10, '{}'::jsonb, TRUE),
  ('restaurant', 'western', 'Western', 'غربي', 20, '{}'::jsonb, TRUE),
  ('restaurant', 'grills', 'Grills', 'مشويات', 30, '{}'::jsonb, TRUE),
  ('restaurant', 'burger', 'Burger', 'برغر', 40, '{}'::jsonb, TRUE),
  ('restaurant', 'pizza', 'Pizza', 'بيتزا', 50, '{}'::jsonb, TRUE),
  ('restaurant', 'chicken', 'Chicken', 'دجاج', 60, '{}'::jsonb, TRUE),
  ('restaurant', 'mandi_madhbi', 'Mandi & Madhbi', 'مندي ومظبي', 70, '{}'::jsonb, TRUE),
  ('restaurant', 'seafood', 'Seafood', 'أسماك ومأكولات بحرية', 80, '{}'::jsonb, TRUE),
  ('restaurant', 'breakfast', 'Breakfast', 'فطور', 90, '{}'::jsonb, TRUE),
  ('restaurant', 'pastries', 'Pastries', 'معجنات', 100, '{}'::jsonb, TRUE),
  ('restaurant', 'desserts', 'Desserts', 'حلويات', 110, '{}'::jsonb, TRUE),
  ('restaurant', 'juices_drinks', 'Juices & Drinks', 'عصائر ومشروبات', 120, '{}'::jsonb, TRUE),
  ('restaurant', 'cafe', 'Cafe', 'كافيه', 130, '{}'::jsonb, TRUE),
  ('restaurant', 'healthy_diet', 'Healthy & Diet', 'صحي ودايت', 140, '{}'::jsonb, TRUE),
  ('restaurant', 'sandwiches_fast_food', 'Sandwiches & Fast Food', 'ساندويشات ووجبات سريعة', 150, '{}'::jsonb, TRUE),
  ('pharmacy', 'prescriptions', 'Prescriptions', 'وصفات طبية', 10, '{"feature":"accepts_prescriptions"}'::jsonb, TRUE),
  ('pharmacy', 'otc', 'OTC', 'أدوية بدون وصفة', 20, '{}'::jsonb, TRUE),
  ('pharmacy', 'vitamins', 'Vitamins', 'فيتامينات', 30, '{}'::jsonb, TRUE),
  ('pharmacy', 'mother_baby', 'Mother & Baby', 'أم وطفل', 40, '{"feature":"mother_baby"}'::jsonb, TRUE),
  ('pharmacy', 'medical_devices', 'Medical Devices', 'أجهزة ومستلزمات طبية', 50, '{"feature":"medical_devices"}'::jsonb, TRUE),
  ('pharmacy', 'open_24h', '24 Hours', '24 ساعة', 60, '{"feature":"open_24h"}'::jsonb, TRUE),
  ('pharmacy', 'personal_care', 'Personal Care', 'عناية شخصية', 70, '{}'::jsonb, TRUE),
  ('pharmacy', 'fast_delivery', 'Fast Delivery', 'توصيل سريع', 80, '{"feature":"fast_delivery"}'::jsonb, TRUE),
  ('sweets_bakery', 'eastern_sweets', 'Eastern Sweets', 'حلويات شرقية', 10, '{}'::jsonb, TRUE),
  ('sweets_bakery', 'western_sweets', 'Western Sweets', 'حلويات غربية', 20, '{}'::jsonb, TRUE),
  ('sweets_bakery', 'cakes_occasions', 'Cakes & Occasions', 'كيك ومناسبات', 30, '{}'::jsonb, TRUE),
  ('sweets_bakery', 'bakery_pastries', 'Bakery & Pastries', 'مخبوزات ومعجنات', 40, '{}'::jsonb, TRUE),
  ('sweets_bakery', 'ice_cream', 'Ice Cream', 'آيس كريم', 50, '{}'::jsonb, TRUE),
  ('sweets_bakery', 'chocolate_gifts', 'Chocolate & Gifts', 'شوكولاتة وهدايا', 60, '{}'::jsonb, TRUE),
  ('coffee_drinks', 'cafe', 'Cafe', 'كافيه', 10, '{}'::jsonb, TRUE),
  ('coffee_drinks', 'juices', 'Juices', 'عصائر', 20, '{}'::jsonb, TRUE),
  ('coffee_drinks', 'specialty', 'Specialty', 'مختص', 30, '{}'::jsonb, TRUE),
  ('coffee_drinks', 'tea_hot', 'Tea & Hot Drinks', 'شاي ومشروبات ساخنة', 40, '{}'::jsonb, TRUE),
  ('coffee_drinks', 'icecream_milkshake', 'Ice Cream & Milkshake', 'آيس كريم وميلك شيك', 50, '{}'::jsonb, TRUE),
  ('personal_care_beauty', 'skin_care', 'Skin Care', 'عناية بالبشرة', 10, '{}'::jsonb, TRUE),
  ('personal_care_beauty', 'hair_care', 'Hair Care', 'عناية بالشعر', 20, '{}'::jsonb, TRUE),
  ('personal_care_beauty', 'makeup', 'Makeup', 'مكياج', 30, '{}'::jsonb, TRUE),
  ('personal_care_beauty', 'perfumes', 'Perfumes', 'عطور', 40, '{}'::jsonb, TRUE),
  ('personal_care_beauty', 'mens_care', 'Men Care', 'عناية رجالية', 50, '{}'::jsonb, TRUE)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  label_en = EXCLUDED.label_en,
  label_ar = EXCLUDED.label_ar,
  order_index = EXCLUDED.order_index,
  metadata_json = EXCLUDED.metadata_json,
  is_active = TRUE,
  updated_at = NOW();

COMMIT;
