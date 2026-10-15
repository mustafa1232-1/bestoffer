-- Reclassify live service offerings into the section that matches their name.
-- Only category links change; pricing, media, moderation, providers, and bookings remain untouched.
BEGIN;

INSERT INTO service_categories (parent_id, level, name, sort_order, is_active, is_public)
VALUES
  (NULL, 1, 'خدمات طبية', 117, TRUE, TRUE),
  (NULL, 1, 'صيانة سيارات متنقلة', 118, TRUE, TRUE),
  (NULL, 1, 'خدمات الطوارئ SOS', 119, TRUE, TRUE)
ON CONFLICT (parent_id_resolved, normalized_name) DO UPDATE
SET is_active = TRUE,
    is_public = TRUE,
    updated_at = NOW();

WITH service_category_map(service_name, category_name) AS (
  VALUES
    ('قياس ضغط الدم', 'خدمات طبية'),
    ('قياس سكر الدم', 'خدمات طبية'),
    ('زرق ابرة', 'خدمات طبية'),
    ('تركيب كانولا', 'خدمات طبية'),
    ('رفع خيط العملية', 'خدمات طبية'),
    ('تركيب صوندة الادرار بولي', 'خدمات طبية'),
    ('فحص الحساسيه', 'خدمات طبية'),
    ('حجامة', 'خدمات طبية'),
    ('ضماده و تنظيف العملية', 'خدمات طبية'),
    ('زوائد لحميه', 'خدمات طبية'),
    ('مسمار قدم', 'خدمات طبية'),
    ('إزالة شامة الوجه', 'خدمات طبية'),
    ('فتح وشد غرف نوم مع نقل', 'نقل أثاث'),
    ('تثبيت ستاند بلازما', 'صيانة أجهزة منزلية'),
    ('تقديم محجر', 'صيانة تكييف وتبريد'),
    ('شد مروحة سقفية', 'صيانة كهرباء'),
    ('صيانة سيارات متنقلة', 'صيانة سيارات متنقلة'),
    ('SOS مساعدة عاجلة', 'خدمات الطوارئ SOS')
), resolved_map AS (
  SELECT
    regexp_replace(lower(m.service_name), '[[:space:]]+', '', 'g') AS normalized_service_name,
    c.id AS category_id
  FROM service_category_map m
  JOIN service_categories c
    ON c.parent_id IS NULL
   AND c.level = 1
   AND c.name = m.category_name
)
UPDATE service_offerings o
SET main_category_id = m.category_id,
    subcategory_id = NULL,
    updated_at = NOW()
FROM resolved_map m
WHERE regexp_replace(lower(o.name), '[[:space:]]+', '', 'g') = m.normalized_service_name
  AND o.main_category_id IS DISTINCT FROM m.category_id;

COMMIT;
