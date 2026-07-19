INSERT INTO service_categories (parent_id, level, name, sort_order, is_active, is_public)
VALUES
  (NULL, 1, 'تنظيف منازل', 26, TRUE, TRUE),
  (NULL, 1, 'تنظيف مكاتب', 27, TRUE, TRUE),
  (NULL, 1, 'تنظيف سجاد', 28, TRUE, TRUE),
  (NULL, 1, 'مكافحة حشرات', 29, TRUE, TRUE),
  (NULL, 1, 'صيانة كهرباء', 30, TRUE, TRUE),
  (NULL, 1, 'صيانة سباكة', 31, TRUE, TRUE),
  (NULL, 1, 'صيانة ثلاجات', 32, TRUE, TRUE),
  (NULL, 1, 'صيانة غسالات', 33, TRUE, TRUE),
  (NULL, 1, 'صيانة أفران', 34, TRUE, TRUE),
  (NULL, 1, 'دهان وديكور', 35, TRUE, TRUE),
  (NULL, 1, 'نجارة', 36, TRUE, TRUE),
  (NULL, 1, 'حدادة', 37, TRUE, TRUE),
  (NULL, 1, 'نقل أثاث', 38, TRUE, TRUE),
  (NULL, 1, 'تركيب أجهزة', 39, TRUE, TRUE),
  (NULL, 1, 'تركيب ستلايت', 40, TRUE, TRUE),
  (NULL, 1, 'تنسيق حدائق', 41, TRUE, TRUE),
  (NULL, 1, 'غسيل سيارات', 42, TRUE, TRUE)
ON CONFLICT (parent_id_resolved, normalized_name) DO UPDATE
SET
  is_active = EXCLUDED.is_active,
  is_public = EXCLUDED.is_public,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();
