-- 169_admin_rbac_foundation.sql
-- المرحلة 2: أساس صلاحيات الإدارة الدقيقة (RBAC + نطاقات + منح فردية + تدقيق).
-- Forward-only. أعمدة جديدة nullable/defaulted؛ لا تتأثر الحسابات القائمة.
-- الصلاحيات تُقرأ من قاعدة البيانات لكل طلب (لا تُخزّن في التوكن).

BEGIN;

-- إصدار الصلاحيات: يُرفع عند أي تغيير على صلاحيات المستخدم حتى يُحدّث العميل
-- قائمته ويُعاد التحقق. (المنع الفعلي يعتمد على القراءة الحية من القاعدة.)
ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS permission_version INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS admin_role_key VARCHAR(48);

-- منح/سحب صلاحية لموظف محدد مع نطاق وتاريخ انتهاء اختياري.
CREATE TABLE IF NOT EXISTS admin_user_permission (
  id                 BIGSERIAL PRIMARY KEY,
  user_id            BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  permission_key     VARCHAR(80) NOT NULL,
  effect             VARCHAR(8) NOT NULL DEFAULT 'grant',
  scope              VARCHAR(16) NOT NULL DEFAULT 'all',
  expires_at         TIMESTAMPTZ,
  reason             TEXT,
  granted_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_admin_user_permission_effect CHECK (effect IN ('grant', 'revoke')),
  CONSTRAINT chk_admin_user_permission_scope
    CHECK (scope IN ('own', 'assigned', 'department', 'all')),
  UNIQUE (user_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_admin_user_permission_user
  ON admin_user_permission (user_id);

-- سجل تغييرات الصلاحيات (تدقيق؛ يُعمّم في المرحلة 11).
CREATE TABLE IF NOT EXISTS admin_permission_change_log (
  id             BIGSERIAL PRIMARY KEY,
  target_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  action         VARCHAR(32) NOT NULL,
  permission_key VARCHAR(80),
  scope          VARCHAR(16),
  role_key       VARCHAR(48),
  before_value   JSONB,
  after_value    JSONB,
  reason         TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_permission_change_log_target
  ON admin_permission_change_log (target_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_permission_change_log_actor
  ON admin_permission_change_log (actor_user_id, created_at DESC);

COMMIT;
