-- 201_support_call_center_p0.sql
-- P0 call-center foundation: support agent presence, automatic routing, and
-- durable SLA warning/escalation markers. Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS support_agent_presence (
  agent_user_id      BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  status             VARCHAR(16) NOT NULL DEFAULT 'offline',
  team               VARCHAR(48),
  skill_domains      JSONB NOT NULL DEFAULT '[]'::jsonb,
  current_ticket_id  BIGINT REFERENCES support_ticket(id) ON DELETE SET NULL,
  last_assigned_at   TIMESTAMPTZ,
  last_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_support_agent_presence_status CHECK (status IN (
    'available','on_ticket','acw','break','offline'
  ))
);

CREATE INDEX IF NOT EXISTS idx_support_agent_presence_routing
  ON support_agent_presence (status, team, last_assigned_at NULLS FIRST, updated_at ASC);

CREATE INDEX IF NOT EXISTS idx_support_agent_presence_domains
  ON support_agent_presence USING GIN (skill_domains);

ALTER TABLE support_ticket
  ADD COLUMN IF NOT EXISTS routed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS routing_strategy VARCHAR(32),
  ADD COLUMN IF NOT EXISTS sla_warning_notified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sla_escalated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS escalation_team VARCHAR(48),
  ADD COLUMN IF NOT EXISTS escalated_to_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS escalation_reason VARCHAR(64);

CREATE INDEX IF NOT EXISTS idx_support_ticket_sla_worker_due
  ON support_ticket (sla_resolution_due_at, sla_first_response_due_at, status)
  WHERE status NOT IN ('RESOLVED','CLOSED');

CREATE INDEX IF NOT EXISTS idx_support_ticket_escalation_team
  ON support_ticket (escalation_team, sla_escalated_at DESC)
  WHERE sla_escalated_at IS NOT NULL;

COMMIT;
