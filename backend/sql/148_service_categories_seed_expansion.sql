INSERT INTO service_categories (parent_id, level, name, sort_order, is_active, is_public)
VALUES
  (NULL, 1, 'تنظيف شقق', 19, TRUE, TRUE),
  (NULL, 1, 'صيانة سبالت', 20, TRUE, TRUE),
  (NULL, 1, 'صيانة طباخات وسخانات', 21, TRUE, TRUE),
  (NULL, 1, 'صيانة أبواب ونوافذ', 22, TRUE, TRUE),
  (NULL, 1, 'خدمات توصيل', 23, TRUE, TRUE),
  (NULL, 1, 'خدمات حدائق', 24, TRUE, TRUE),
  (NULL, 1, 'خدمات تركيب كاميرات', 25, TRUE, TRUE)
ON CONFLICT (parent_id_resolved, normalized_name) DO UPDATE
SET
  is_active = EXCLUDED.is_active,
  is_public = EXCLUDED.is_public,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();
