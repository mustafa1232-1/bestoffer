-- P1/P2 call-center tooling: canned replies, knowledge base, callbacks and SLA metrics.

CREATE TABLE IF NOT EXISTS support_canned_response (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(160) NOT NULL,
  body TEXT NOT NULL,
  domain VARCHAR(24),
  type VARCHAR(24),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_canned_response_lookup
  ON support_canned_response (is_active, domain, type, title);

CREATE TABLE IF NOT EXISTS support_knowledge_article (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(200) NOT NULL,
  body TEXT NOT NULL,
  domain VARCHAR(24),
  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_knowledge_article_lookup
  ON support_knowledge_article (is_published, domain, title);

CREATE TABLE IF NOT EXISTS support_ticket_callback (
  id BIGSERIAL PRIMARY KEY,
  ticket_id BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  customer_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  assigned_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  phone VARCHAR(32),
  status VARCHAR(16) NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','completed','cancelled','missed')),
  completed_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_callback_ticket
  ON support_ticket_callback (ticket_id, scheduled_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_ticket_callback_assignee
  ON support_ticket_callback (assigned_user_id, status, scheduled_at);

CREATE INDEX IF NOT EXISTS idx_support_ticket_callback_status_due
  ON support_ticket_callback (status, scheduled_at);
