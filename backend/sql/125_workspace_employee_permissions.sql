BEGIN;

ALTER TABLE merchant_employee_profile
  ADD COLUMN IF NOT EXISTS display_name VARCHAR(180),
  ADD COLUMN IF NOT EXISTS contact_email VARCHAR(320),
  ADD COLUMN IF NOT EXISTS permissions_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invited_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_employee_profile_merchant_state
  ON merchant_employee_profile (merchant_id, is_active, archived_at DESC, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_employee_profile_contact_email
  ON merchant_employee_profile (merchant_id, contact_email)
  WHERE contact_email IS NOT NULL;

CREATE TABLE IF NOT EXISTS service_provider_employee_profile (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role_tag VARCHAR(80) NOT NULL DEFAULT 'staff',
  display_name VARCHAR(180),
  contact_email VARCHAR(320),
  permissions_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  archived_at TIMESTAMPTZ,
  notes TEXT,
  invited_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider_id, employee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_service_provider_employee_profile_provider_state
  ON service_provider_employee_profile (provider_id, is_active, archived_at DESC, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_provider_employee_profile_contact_email
  ON service_provider_employee_profile (provider_id, contact_email)
  WHERE contact_email IS NOT NULL;

CREATE TABLE IF NOT EXISTS workspace_employee_activity_log (
  id BIGSERIAL PRIMARY KEY,
  workspace_kind VARCHAR(24) NOT NULL,
  workspace_id BIGINT NOT NULL,
  employee_profile_id BIGINT,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(40) NOT NULL DEFAULT '',
  action_key VARCHAR(120) NOT NULL,
  reason TEXT,
  old_value JSONB NOT NULL DEFAULT '{}'::jsonb,
  new_value JSONB NOT NULL DEFAULT '{}'::jsonb,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (workspace_kind IN ('merchant', 'service_provider'))
);

CREATE INDEX IF NOT EXISTS idx_workspace_employee_activity_log_workspace
  ON workspace_employee_activity_log (workspace_kind, workspace_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_workspace_employee_activity_log_employee
  ON workspace_employee_activity_log (employee_user_id, created_at DESC, id DESC);

COMMIT;
