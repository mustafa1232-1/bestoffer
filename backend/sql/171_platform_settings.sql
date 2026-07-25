-- 171_platform_settings.sql
-- المرحلة 8: إعدادات مركزية للمنصّة (رقم الدعم وغيره) key/value.
-- Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS platform_setting (
  key                VARCHAR(80) PRIMARY KEY,
  value_json         JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;
