BEGIN;

CREATE TABLE IF NOT EXISTS admin_audit_event (
  id BIGSERIAL PRIMARY KEY,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(40),
  action_key VARCHAR(120) NOT NULL,
  summary TEXT NOT NULL,
  target_type VARCHAR(80),
  target_id BIGINT,
  target_label VARCHAR(200),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_event_created
ON admin_audit_event(created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_event_actor
ON admin_audit_event(actor_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_event_action
ON admin_audit_event(action_key, created_at DESC, id DESC);

COMMIT;
