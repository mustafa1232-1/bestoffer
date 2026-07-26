-- 174_admin_role_management_security_closure.sql
-- RBAC closure: custom roles, role permissions, and maker/approver foundation.
-- No users, credentials, or demo data are created here.

BEGIN;

CREATE TABLE IF NOT EXISTS admin_role (
  role_key           VARCHAR(48) PRIMARY KEY,
  display_name       TEXT NOT NULL,
  description        TEXT,
  category           VARCHAR(48) NOT NULL DEFAULT 'custom',
  is_system          BOOLEAN NOT NULL DEFAULT FALSE,
  is_archived        BOOLEAN NOT NULL DEFAULT FALSE,
  archived_at        TIMESTAMPTZ,
  archived_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  copied_from_role_key VARCHAR(48),
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_admin_role_key_format
    CHECK (role_key ~ '^[a-z][a-z0-9_]{2,47}$')
);

CREATE TABLE IF NOT EXISTS admin_role_permission (
  role_key           VARCHAR(48) NOT NULL REFERENCES admin_role(role_key) ON DELETE CASCADE,
  permission_key     VARCHAR(80) NOT NULL,
  scope              VARCHAR(16) NOT NULL DEFAULT 'all',
  granted_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (role_key, permission_key),
  CONSTRAINT chk_admin_role_permission_scope
    CHECK (scope IN ('own', 'assigned', 'department', 'all'))
);

CREATE INDEX IF NOT EXISTS idx_admin_role_active
  ON admin_role(is_archived, category, role_key);

CREATE INDEX IF NOT EXISTS idx_admin_role_permission_role
  ON admin_role_permission(role_key, permission_key);

CREATE TABLE IF NOT EXISTS maker_approval_request (
  id                 BIGSERIAL PRIMARY KEY,
  operation_key      VARCHAR(80) NOT NULL,
  entity_type        VARCHAR(80),
  entity_id          TEXT,
  status             VARCHAR(24) NOT NULL DEFAULT 'PENDING',
  payload_json       JSONB NOT NULL DEFAULT '{}'::jsonb,
  reason             TEXT NOT NULL,
  maker_user_id      BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  approver_user_id   BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  executed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approval_permission_key VARCHAR(80),
  idempotency_key    VARCHAR(120),
  expires_at         TIMESTAMPTZ,
  decided_at         TIMESTAMPTZ,
  executed_at        TIMESTAMPTZ,
  audit_json         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_maker_approval_status CHECK (
    status IN (
      'PENDING',
      'APPROVED',
      'REJECTED',
      'EXECUTED',
      'CANCELLED',
      'EXPIRED'
    )
  ),
  CONSTRAINT chk_maker_approval_reason_not_empty CHECK (length(trim(reason)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_maker_approval_idempotency
  ON maker_approval_request(operation_key, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_maker_approval_status
  ON maker_approval_request(status, created_at DESC);

ALTER TABLE admin_permission_change_log
  ADD COLUMN IF NOT EXISTS target_role_key VARCHAR(48),
  ADD COLUMN IF NOT EXISTS sensitive BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS recent_auth_verified_at TIMESTAMPTZ;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS recent_auth_verified_at TIMESTAMPTZ;

COMMIT;
