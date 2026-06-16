-- Purpose:
-- Operational observability and reliability primitives used by:
-- - Admin operational centers (notifications/crash/security/device health)
-- - Push delivery/action tracking
-- - Feature flags and role overrides

BEGIN;

CREATE TABLE IF NOT EXISTS ops_alert (
  id BIGSERIAL PRIMARY KEY,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('info', 'low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'acknowledged', 'resolved', 'ignored')),
  title TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key TEXT NULL,
  affected_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  affected_role TEXT NULL,
  entity_type TEXT NULL,
  entity_id BIGINT NULL,
  acked_by_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  acked_at TIMESTAMPTZ NULL,
  resolved_by_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  resolved_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ops_alert_status_severity_created
  ON ops_alert(status, severity, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_alert_event_created
  ON ops_alert(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_alert_affected_user_created
  ON ops_alert(affected_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ops_alert_ack (
  id BIGSERIAL PRIMARY KEY,
  alert_id BIGINT NOT NULL REFERENCES ops_alert(id) ON DELETE CASCADE,
  actor_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  from_status TEXT NOT NULL,
  to_status TEXT NOT NULL,
  note TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ops_alert_ack_alert_created
  ON ops_alert_ack(alert_id, created_at DESC);

CREATE TABLE IF NOT EXISTS app_notification (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  type VARCHAR(80) NOT NULL,
  title VARCHAR(200) NOT NULL,
  body TEXT,
  payload JSONB,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_app_notification_user_created
  ON app_notification (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app_notification_user_unread
  ON app_notification (user_id, is_read);

CREATE TABLE IF NOT EXISTS notification_delivery_event (
  id BIGSERIAL PRIMARY KEY,
  notification_id BIGINT NULL REFERENCES app_notification(id) ON DELETE SET NULL,
  user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  push_token TEXT NULL,
  platform TEXT NULL,
  channel_id TEXT NULL,
  target TEXT NULL,
  event_status TEXT NOT NULL
    CHECK (event_status IN ('queued', 'sent', 'delivered', 'opened', 'failed', 'dead_token', 'retry', 'suppressed')),
  error_code TEXT NULL,
  error_message TEXT NULL,
  latency_ms INTEGER NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_event_created
  ON notification_delivery_event(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_event_status_created
  ON notification_delivery_event(event_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_event_notification_created
  ON notification_delivery_event(notification_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_event_user_created
  ON notification_delivery_event(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notification_action_event (
  id BIGSERIAL PRIMARY KEY,
  notification_id BIGINT NULL REFERENCES app_notification(id) ON DELETE SET NULL,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  action_id TEXT NOT NULL,
  target TEXT NULL,
  entity_type TEXT NULL,
  entity_id BIGINT NULL,
  request_state TEXT NOT NULL DEFAULT 'opened'
    CHECK (request_state IN ('accepted', 'rejected', 'stale', 'failed', 'ignored', 'opened')),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_action_event_user_created
  ON notification_action_event(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_action_event_notification_created
  ON notification_action_event(notification_id, created_at DESC);

CREATE TABLE IF NOT EXISTS device_push_health (
  push_token TEXT PRIMARY KEY,
  user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  platform TEXT NULL,
  last_status TEXT NULL,
  last_error_code TEXT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  last_seen_at TIMESTAMPTZ NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_push_health_user_updated
  ON device_push_health(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_device_push_health_status_updated
  ON device_push_health(last_status, updated_at DESC);

CREATE TABLE IF NOT EXISTS app_crash_event (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  app_role TEXT NULL,
  platform TEXT NULL,
  app_version TEXT NULL,
  source TEXT NOT NULL,
  message TEXT NOT NULL,
  stack_trace TEXT NULL,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_crash_event_created
  ON app_crash_event(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app_crash_event_platform_created
  ON app_crash_event(platform, created_at DESC);

CREATE TABLE IF NOT EXISTS feature_flag (
  id BIGSERIAL PRIMARY KEY,
  flag_key TEXT NOT NULL UNIQUE,
  description TEXT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  rollout_percent INTEGER NOT NULL DEFAULT 0
    CHECK (rollout_percent >= 0 AND rollout_percent <= 100),
  target_roles TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feature_flag_enabled_updated
  ON feature_flag(is_enabled, updated_at DESC);

CREATE TABLE IF NOT EXISTS role_permission_override (
  id BIGSERIAL PRIMARY KEY,
  role_key TEXT NOT NULL,
  capability_key TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL,
  notes TEXT NULL,
  updated_by_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (role_key, capability_key)
);

CREATE INDEX IF NOT EXISTS idx_role_permission_override_role_updated
  ON role_permission_override(role_key, updated_at DESC);

COMMIT;
