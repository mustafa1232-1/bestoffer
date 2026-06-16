CREATE TABLE IF NOT EXISTS ops_incidents (
  id BIGSERIAL PRIMARY KEY,
  source VARCHAR(80) NOT NULL,
  severity VARCHAR(10) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'open',
  affected_service VARCHAR(120),
  affected_module VARCHAR(120),
  title VARCHAR(300) NOT NULL,
  summary TEXT,
  symptoms_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  probable_root_cause TEXT,
  evidence_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  suggested_mitigation TEXT,
  long_term_fix TEXT,
  risk_level VARCHAR(20) NOT NULL DEFAULT 'medium',
  created_by BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  assigned_to BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  CONSTRAINT ops_incidents_severity_chk CHECK (severity IN ('SEV1','SEV2','SEV3','SEV4')),
  CONSTRAINT ops_incidents_risk_chk CHECK (risk_level IN ('low','medium','high','critical'))
);

CREATE TABLE IF NOT EXISTS ops_alerts (
  id BIGSERIAL PRIMARY KEY,
  incident_id BIGINT NOT NULL REFERENCES ops_incidents(id) ON DELETE CASCADE,
  source VARCHAR(80) NOT NULL,
  payload_redacted_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops_actions (
  id BIGSERIAL PRIMARY KEY,
  incident_id BIGINT NOT NULL REFERENCES ops_incidents(id) ON DELETE CASCADE,
  action_type VARCHAR(120) NOT NULL,
  risk_level VARCHAR(20) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'pending_approval',
  requested_by BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_by BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  rejected_by BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  input_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  output_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  executed_at TIMESTAMPTZ,
  CONSTRAINT ops_actions_risk_chk CHECK (risk_level IN ('low','medium','high','critical'))
);

CREATE TABLE IF NOT EXISTS ops_action_approvals (
  id BIGSERIAL PRIMARY KEY,
  action_id BIGINT NOT NULL REFERENCES ops_actions(id) ON DELETE CASCADE,
  approver_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  decision VARCHAR(20) NOT NULL,
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ops_action_approvals_decision_chk CHECK (decision IN ('approved','rejected'))
);

CREATE TABLE IF NOT EXISTS ops_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(80),
  action VARCHAR(120) NOT NULL,
  target_type VARCHAR(80) NOT NULL,
  target_id VARCHAR(120),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address VARCHAR(128),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops_runbooks (
  id BIGSERIAL PRIMARY KEY,
  slug VARCHAR(120) NOT NULL UNIQUE,
  title VARCHAR(260) NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops_settings (
  id BIGSERIAL PRIMARY KEY,
  key VARCHAR(160) NOT NULL UNIQUE,
  value_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops_notifications (
  id BIGSERIAL PRIMARY KEY,
  incident_id BIGINT REFERENCES ops_incidents(id) ON DELETE CASCADE,
  user_id BIGINT REFERENCES app_user(id) ON DELETE CASCADE,
  channel VARCHAR(60) NOT NULL,
  title VARCHAR(220) NOT NULL,
  body TEXT NOT NULL,
  priority VARCHAR(30) NOT NULL DEFAULT 'high',
  status VARCHAR(30) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ops_incidents_status_created
  ON ops_incidents (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_incidents_severity_created
  ON ops_incidents (severity, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_incidents_source_created
  ON ops_incidents (source, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_alerts_incident_received
  ON ops_alerts (incident_id, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_actions_incident_created
  ON ops_actions (incident_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_actions_status_created
  ON ops_actions (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_action_approvals_action_created
  ON ops_action_approvals (action_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_logs_target_created
  ON ops_audit_logs (target_type, target_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_notifications_user_created
  ON ops_notifications (user_id, created_at DESC);

INSERT INTO role_permission_override (role_key, capability_key, is_enabled, notes)
VALUES
  ('super_admin', 'ai_dev_support_access', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_view_incidents', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_approve_action', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_reject_action', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_request_code_fix', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_create_github_issue', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_manage_settings', TRUE, 'AI DEV SUPPORT default access'),
  ('super_admin', 'ai_dev_support_view_audit_logs', TRUE, 'AI DEV SUPPORT default access')
ON CONFLICT (role_key, capability_key) DO NOTHING;
