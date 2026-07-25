-- 170_unified_audit_log.sql
-- المرحلة 11: توحيد سجل التدقيق على admin_audit_event (بلا جدول موازٍ).
-- Forward-only؛ أعمدة جديدة nullable/defaulted.

BEGIN;

ALTER TABLE admin_audit_event
  ADD COLUMN IF NOT EXISTS reason          TEXT,
  ADD COLUMN IF NOT EXISTS result          VARCHAR(16) NOT NULL DEFAULT 'ok',
  ADD COLUMN IF NOT EXISTS permission_key  VARCHAR(80),
  ADD COLUMN IF NOT EXISTS ip_address      VARCHAR(128),
  ADD COLUMN IF NOT EXISTS session_id      BIGINT,
  ADD COLUMN IF NOT EXISTS ticket_id       BIGINT,
  ADD COLUMN IF NOT EXISTS before_json     JSONB,
  ADD COLUMN IF NOT EXISTS after_json      JSONB;

CREATE INDEX IF NOT EXISTS idx_admin_audit_event_target
  ON admin_audit_event (target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_event_action
  ON admin_audit_event (action_key, created_at DESC);

COMMIT;
