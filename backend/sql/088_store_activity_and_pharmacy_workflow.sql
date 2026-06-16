BEGIN;

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS activity_type VARCHAR(80),
  ADD COLUMN IF NOT EXISTS discovery_subcategory VARCHAR(120),
  ADD COLUMN IF NOT EXISTS service_flags_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS supports_chat BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS supports_attachments BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS supports_pharmacy_workflow BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS badges_json JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS store_activity_definition (
  activity_type VARCHAR(80) PRIMARY KEY,
  base_type merchant_type NOT NULL,
  display_name_en VARCHAR(160) NOT NULL,
  display_name_ar VARCHAR(160) NOT NULL,
  has_discovery_subcategories BOOLEAN NOT NULL DEFAULT FALSE,
  supports_chat BOOLEAN NOT NULL DEFAULT FALSE,
  supports_attachments BOOLEAN NOT NULL DEFAULT FALSE,
  supports_pharmacy_workflow BOOLEAN NOT NULL DEFAULT FALSE,
  internal_category_mode VARCHAR(120) NOT NULL DEFAULT 'merchant_defined_with_templates',
  default_service_flags_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  default_badges_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS store_activity_discovery_option (
  id BIGSERIAL PRIMARY KEY,
  activity_type VARCHAR(80) NOT NULL REFERENCES store_activity_definition(activity_type) ON DELETE CASCADE,
  code VARCHAR(120) NOT NULL,
  label_en VARCHAR(160) NOT NULL,
  label_ar VARCHAR(160) NOT NULL,
  order_index INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(activity_type, code)
);

CREATE TABLE IF NOT EXISTS store_activity_internal_category_template (
  id BIGSERIAL PRIMARY KEY,
  activity_type VARCHAR(80) NOT NULL REFERENCES store_activity_definition(activity_type) ON DELETE CASCADE,
  code VARCHAR(120) NOT NULL,
  name_en VARCHAR(160) NOT NULL,
  name_ar VARCHAR(160) NOT NULL,
  icon VARCHAR(80),
  order_index INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(activity_type, code)
);

ALTER TABLE merchant_category
  ADD COLUMN IF NOT EXISTS icon VARCHAR(80),
  ADD COLUMN IF NOT EXISTS order_index INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS source VARCHAR(40) NOT NULL DEFAULT 'custom';

UPDATE merchant_category
SET order_index = COALESCE(NULLIF(order_index, 0), sort_order, 0)
WHERE TRUE;

ALTER TABLE product
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS requires_review BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS pharmacy_conversation (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  activity_type VARCHAR(80) NOT NULL DEFAULT 'pharmacy',
  conversation_type VARCHAR(80) NOT NULL DEFAULT 'pharmacy_direct',
  status VARCHAR(80) NOT NULL DEFAULT 'open',
  linked_order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  last_message_at TIMESTAMPTZ,
  closed_reason VARCHAR(120),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pharmacy_proposed_cart (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL REFERENCES pharmacy_conversation(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  status VARCHAR(80) NOT NULL DEFAULT 'draft',
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes TEXT,
  expires_at TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  revision_requested_at TIMESTAMPTZ,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(conversation_id, version)
);

CREATE TABLE IF NOT EXISTS pharmacy_proposed_cart_item (
  id BIGSERIAL PRIMARY KEY,
  proposed_cart_id BIGINT NOT NULL REFERENCES pharmacy_proposed_cart(id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES product(id) ON DELETE SET NULL,
  product_name VARCHAR(220) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total >= 0),
  alternative_group_id VARCHAR(80),
  note TEXT,
  requires_prescription BOOLEAN NOT NULL DEFAULT FALSE,
  requires_review BOOLEAN NOT NULL DEFAULT FALSE,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pharmacy_attachment (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL REFERENCES pharmacy_conversation(id) ON DELETE CASCADE,
  uploader_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  file_url TEXT NOT NULL,
  storage_key TEXT,
  attachment_mime_type VARCHAR(160),
  file_size_bytes BIGINT,
  original_file_name TEXT,
  is_sensitive BOOLEAN NOT NULL DEFAULT TRUE,
  retention_expires_at TIMESTAMPTZ,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pharmacy_message (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL REFERENCES pharmacy_conversation(id) ON DELETE CASCADE,
  sender_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  sender_type VARCHAR(40) NOT NULL,
  message_type VARCHAR(40) NOT NULL DEFAULT 'text',
  text TEXT,
  attachment_id BIGINT REFERENCES pharmacy_attachment(id) ON DELETE SET NULL,
  proposed_cart_id BIGINT REFERENCES pharmacy_proposed_cart(id) ON DELETE SET NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pharmacy_attachment_access_audit (
  id BIGSERIAL PRIMARY KEY,
  attachment_id BIGINT NOT NULL REFERENCES pharmacy_attachment(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(40),
  action VARCHAR(40) NOT NULL,
  access_granted BOOLEAN NOT NULL DEFAULT FALSE,
  ip_address VARCHAR(64),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pharmacy_conversation_event_history (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL REFERENCES pharmacy_conversation(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  event_type VARCHAR(80) NOT NULL,
  from_status VARCHAR(80),
  to_status VARCHAR(80),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS source_type VARCHAR(40) NOT NULL DEFAULT 'normal_store',
  ADD COLUMN IF NOT EXISTS order_flow_type VARCHAR(80) NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS pharmacy_conversation_id BIGINT REFERENCES pharmacy_conversation(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS pharmacy_flow_status VARCHAR(80);

CREATE TABLE IF NOT EXISTS pharmacy_retention_job_run (
  id BIGSERIAL PRIMARY KEY,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  action VARCHAR(80) NOT NULL,
  processed_count INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

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
  default_badges_json
)
VALUES
  ('restaurant', 'restaurant', 'Restaurant', 'مطعم', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('pharmacy', 'market', 'Pharmacy', 'صيدلية', TRUE, TRUE, TRUE, TRUE, 'merchant_defined_with_templates_and_constraints', '{"accepts_prescriptions": true, "supports_chat": true, "supports_attachments": true}'::jsonb, '["prescriptions","delivery"]'::jsonb),
  ('supermarket', 'market', 'Supermarket', 'سوبرماركت', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('construction', 'market', 'Construction & Tools', 'مواد إنشائية وعدة', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('sweets_bakery', 'restaurant', 'Sweets & Bakery', 'حلويات ومخبوزات', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('coffee_drinks', 'restaurant', 'Coffee & Drinks', 'قهوة ومشروبات', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('electronics_mobile', 'market', 'Electronics & Mobile', 'إلكترونيات وموبايل', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('personal_care_beauty', 'market', 'Personal Care & Beauty', 'عناية شخصية وتجميل', TRUE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb),
  ('market', 'market', 'General Store', 'متجر عام', FALSE, FALSE, FALSE, FALSE, 'merchant_defined_with_templates', '{}'::jsonb, '[]'::jsonb)
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

INSERT INTO store_activity_discovery_option (activity_type, code, label_en, label_ar, order_index, metadata_json)
VALUES
  ('restaurant', 'eastern', 'Eastern', 'شرقي', 10, '{}'::jsonb),
  ('restaurant', 'western', 'Western', 'غربي', 20, '{}'::jsonb),
  ('restaurant', 'grills', 'Grills', 'مشويات', 30, '{}'::jsonb),
  ('restaurant', 'burger', 'Burger', 'برغر', 40, '{}'::jsonb),
  ('restaurant', 'pizza', 'Pizza', 'بيتزا', 50, '{}'::jsonb),
  ('restaurant', 'chicken', 'Chicken', 'دجاج', 60, '{}'::jsonb),
  ('restaurant', 'breakfast', 'Breakfast', 'فطور', 70, '{}'::jsonb),
  ('restaurant', 'healthy', 'Healthy', 'صحي ودايت', 80, '{}'::jsonb),
  ('pharmacy', 'prescriptions', 'Prescription', 'وصفات طبية', 10, '{"feature": "accepts_prescriptions"}'::jsonb),
  ('pharmacy', 'otc', 'OTC', 'أدوية بدون وصفة', 20, '{}'::jsonb),
  ('pharmacy', 'vitamins', 'Vitamins', 'فيتامينات', 30, '{}'::jsonb),
  ('pharmacy', 'mother_baby', 'Mother & Baby', 'أم وطفل', 40, '{"feature": "mother_baby"}'::jsonb),
  ('pharmacy', 'medical_devices', 'Medical Devices', 'أجهزة ومستلزمات طبية', 50, '{"feature": "medical_devices"}'::jsonb),
  ('pharmacy', 'open_24h', '24 Hours', '24 ساعة', 60, '{"feature": "open_24h"}'::jsonb),
  ('sweets_bakery', 'eastern_sweets', 'Eastern Sweets', 'حلويات شرقية', 10, '{}'::jsonb),
  ('sweets_bakery', 'western_sweets', 'Western Sweets', 'حلويات غربية', 20, '{}'::jsonb),
  ('sweets_bakery', 'cakes', 'Cakes', 'كيك ومناسبات', 30, '{}'::jsonb),
  ('coffee_drinks', 'cafe', 'Cafe', 'كافيه', 10, '{}'::jsonb),
  ('coffee_drinks', 'juices', 'Juices', 'عصائر', 20, '{}'::jsonb),
  ('coffee_drinks', 'specialty', 'Specialty', 'مختص', 30, '{}'::jsonb),
  ('personal_care_beauty', 'skin_care', 'Skin Care', 'عناية بالبشرة', 10, '{}'::jsonb),
  ('personal_care_beauty', 'hair_care', 'Hair Care', 'عناية بالشعر', 20, '{}'::jsonb),
  ('personal_care_beauty', 'perfumes', 'Perfumes', 'عطور', 30, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  label_en = EXCLUDED.label_en,
  label_ar = EXCLUDED.label_ar,
  order_index = EXCLUDED.order_index,
  metadata_json = EXCLUDED.metadata_json,
  is_active = TRUE,
  updated_at = NOW();

INSERT INTO store_activity_internal_category_template (
  activity_type,
  code,
  name_en,
  name_ar,
  icon,
  order_index,
  metadata_json
)
VALUES
  ('restaurant', 'grills', 'Grills', 'المشويات', 'grill', 10, '{}'::jsonb),
  ('restaurant', 'rice_stews', 'Rice & Stews', 'التمن والمرق', 'rice', 20, '{}'::jsonb),
  ('restaurant', 'appetizers', 'Appetizers', 'المقبلات', 'restaurant', 30, '{}'::jsonb),
  ('restaurant', 'soups', 'Soups', 'الشوربات', 'soup_kitchen', 40, '{}'::jsonb),
  ('restaurant', 'drinks', 'Drinks', 'المشروبات', 'local_drink', 50, '{}'::jsonb),
  ('restaurant', 'desserts', 'Desserts', 'الحلويات', 'cake', 60, '{}'::jsonb),
  ('supermarket', 'groceries', 'Groceries', 'مواد غذائية', 'shopping_bag', 10, '{}'::jsonb),
  ('supermarket', 'drinks', 'Drinks', 'مشروبات', 'local_drink', 20, '{}'::jsonb),
  ('supermarket', 'dairy', 'Dairy', 'ألبان وأجبان', 'egg', 30, '{}'::jsonb),
  ('supermarket', 'cleaning', 'Cleaning', 'منظفات', 'cleaning_services', 40, '{}'::jsonb),
  ('supermarket', 'personal_care', 'Personal Care', 'عناية شخصية', 'face', 50, '{}'::jsonb),
  ('construction', 'cement_bonding', 'Cement & Bonding', 'إسمنت ومواد ربط', 'construction', 10, '{}'::jsonb),
  ('construction', 'blocks_bricks', 'Blocks & Bricks', 'طابوق وبلوك', 'view_module', 20, '{}'::jsonb),
  ('construction', 'steel_metals', 'Steel & Metals', 'حديد ومعادن', 'hardware', 30, '{}'::jsonb),
  ('construction', 'plumbing', 'Plumbing', 'سباكة', 'plumbing', 40, '{}'::jsonb),
  ('construction', 'electrical', 'Electrical', 'كهرباء وتمديدات', 'electrical_services', 50, '{}'::jsonb),
  ('construction', 'power_tools', 'Power Tools', 'عدد كهربائية', 'build', 60, '{}'::jsonb),
  ('pharmacy', 'rx', 'Prescription Medicines', 'أدوية بوصفة', 'medical_services', 10, '{"requiresPrescription": true}'::jsonb),
  ('pharmacy', 'otc', 'OTC Medicines', 'أدوية بدون وصفة', 'medication', 20, '{}'::jsonb),
  ('pharmacy', 'pain_fever', 'Pain & Fever', 'مسكنات وخافض حرارة', 'healing', 30, '{}'::jsonb),
  ('pharmacy', 'cold_flu', 'Cold & Flu', 'زكام وسعال وإنفلونزا', 'masks', 40, '{}'::jsonb),
  ('pharmacy', 'allergy_sinus', 'Allergy & Sinus', 'حساسية وجيوب أنفية', 'air', 50, '{}'::jsonb),
  ('pharmacy', 'digestive', 'Digestive Health', 'معدة وهضم', 'local_hospital', 60, '{}'::jsonb),
  ('pharmacy', 'vitamins', 'Vitamins & Supplements', 'فيتامينات ومكملات', 'spa', 70, '{}'::jsonb),
  ('pharmacy', 'mother_baby', 'Mother & Baby', 'أم وطفل', 'child_friendly', 80, '{}'::jsonb),
  ('pharmacy', 'first_aid', 'First Aid', 'إسعافات أولية', 'medical_information', 90, '{}'::jsonb),
  ('pharmacy', 'medical_devices', 'Medical Devices', 'أجهزة ومستلزمات طبية', 'monitor_heart', 100, '{}'::jsonb)
ON CONFLICT (activity_type, code) DO UPDATE
SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  icon = EXCLUDED.icon,
  order_index = EXCLUDED.order_index,
  metadata_json = EXCLUDED.metadata_json,
  is_active = TRUE,
  updated_at = NOW();

UPDATE merchant
SET activity_type = CASE
    WHEN activity_type IS NULL OR TRIM(activity_type) = '' THEN
      CASE WHEN type::text = 'restaurant' THEN 'restaurant' ELSE 'market' END
    ELSE activity_type
  END
WHERE TRUE;

UPDATE merchant m
SET
  supports_chat = d.supports_chat,
  supports_attachments = d.supports_attachments,
  supports_pharmacy_workflow = d.supports_pharmacy_workflow,
  service_flags_json = COALESCE(NULLIF(m.service_flags_json, '{}'::jsonb), d.default_service_flags_json),
  badges_json = COALESCE(NULLIF(m.badges_json, '[]'::jsonb), d.default_badges_json)
FROM store_activity_definition d
WHERE d.activity_type = m.activity_type;

WITH merchants_without_categories AS (
  SELECT m.id, m.activity_type
  FROM merchant m
  WHERE NOT EXISTS (
    SELECT 1
    FROM merchant_category c
    WHERE c.merchant_id = m.id
  )
)
INSERT INTO merchant_category (
  merchant_id,
  name,
  sort_order,
  order_index,
  icon,
  is_active,
  source
)
SELECT
  m.id,
  t.name_ar,
  t.order_index,
  t.order_index,
  t.icon,
  TRUE,
  'template'
FROM merchants_without_categories m
JOIN store_activity_internal_category_template t
  ON t.activity_type = m.activity_type
 AND t.is_active = TRUE
ORDER BY m.id, t.order_index
ON CONFLICT (merchant_id, name) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_merchant_activity_type
ON merchant(activity_type);

CREATE INDEX IF NOT EXISTS idx_merchant_activity_discovery
ON merchant(activity_type, discovery_subcategory);

CREATE INDEX IF NOT EXISTS idx_activity_discovery_option_activity
ON store_activity_discovery_option(activity_type, is_active, order_index);

CREATE INDEX IF NOT EXISTS idx_activity_template_activity
ON store_activity_internal_category_template(activity_type, is_active, order_index);

CREATE INDEX IF NOT EXISTS idx_merchant_category_merchant_active_order
ON merchant_category(merchant_id, is_active, order_index, id);

CREATE INDEX IF NOT EXISTS idx_product_pharmacy_flags
ON product(merchant_id, category_id, requires_prescription, requires_review, is_available);

CREATE INDEX IF NOT EXISTS idx_pharmacy_conversation_merchant_status
ON pharmacy_conversation(merchant_id, status, last_message_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_pharmacy_conversation_customer_status
ON pharmacy_conversation(customer_user_id, status, last_message_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_pharmacy_message_conversation
ON pharmacy_message(conversation_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_pharmacy_attachment_conversation
ON pharmacy_attachment(conversation_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_pharmacy_proposed_cart_conversation
ON pharmacy_proposed_cart(conversation_id, version DESC);

CREATE INDEX IF NOT EXISTS idx_pharmacy_proposed_cart_item_cart
ON pharmacy_proposed_cart_item(proposed_cart_id, id);

CREATE INDEX IF NOT EXISTS idx_pharmacy_attachment_access_audit_attachment
ON pharmacy_attachment_access_audit(attachment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pharmacy_attachment_access_audit_actor
ON pharmacy_attachment_access_audit(actor_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_pharmacy_flow
ON customer_order(source_type, order_flow_type, pharmacy_flow_status, created_at DESC);

COMMIT;
