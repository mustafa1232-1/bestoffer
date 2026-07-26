-- 172_support_tickets.sql
-- المرحلة 4: نظام تذاكر دعم موحّد لكل تطبيقات مسلكي (polymorphic link + SLA +
-- محادثة داخلية/ظاهرة + timeline غير قابل للتلاعب). Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS support_ticket (
  id                        BIGSERIAL PRIMARY KEY,
  ticket_number             VARCHAR(24) UNIQUE,
  user_id                   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  domain                    VARCHAR(24) NOT NULL,
  type                      VARCHAR(24) NOT NULL,
  priority                  VARCHAR(12) NOT NULL DEFAULT 'normal',
  subject                   VARCHAR(240) NOT NULL,
  description               TEXT,
  status                    VARCHAR(28) NOT NULL DEFAULT 'NEW',
  assigned_user_id          BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  team                      VARCHAR(48),
  entity_type               VARCHAR(48),
  entity_id                 BIGINT,
  sla_first_response_due_at TIMESTAMPTZ,
  sla_resolution_due_at     TIMESTAMPTZ,
  first_response_at         TIMESTAMPTZ,
  resolved_at               TIMESTAMPTZ,
  closed_at                 TIMESTAMPTZ,
  resolution_summary        TEXT,
  resolution_reason         VARCHAR(64),
  rating                    SMALLINT CHECK (rating IS NULL OR (rating BETWEEN 1 AND 5)),
  rating_speed              SMALLINT CHECK (rating_speed IS NULL OR (rating_speed BETWEEN 1 AND 5)),
  rating_quality            SMALLINT CHECK (rating_quality IS NULL OR (rating_quality BETWEEN 1 AND 5)),
  rating_comment            TEXT,
  reopened_count            INT NOT NULL DEFAULT 0,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_support_ticket_domain CHECK (domain IN (
    'SHOPPING','DELIVERY','TAXI','SERVICES','REAL_ESTATE','CARS','JOBS',
    'COMMUNITY','ACCOUNT','PAYMENTS','OTHER'
  )),
  CONSTRAINT chk_support_ticket_type CHECK (type IN (
    'PROBLEM','COMPLAINT','QUESTION','SUGGESTION','SAFETY','REFUND','OTHER'
  )),
  CONSTRAINT chk_support_ticket_priority CHECK (priority IN (
    'low','normal','high','urgent'
  )),
  CONSTRAINT chk_support_ticket_status CHECK (status IN (
    'NEW','TRIAGED','ASSIGNED','IN_PROGRESS','WAITING_FOR_CUSTOMER',
    'WAITING_FOR_MERCHANT','WAITING_FOR_CAPTAIN','WAITING_FOR_DELIVERY',
    'ESCALATED','RESOLVED','CLOSED','REOPENED'
  ))
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_user
  ON support_ticket (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_ticket_status
  ON support_ticket (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_ticket_assigned
  ON support_ticket (assigned_user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_ticket_entity
  ON support_ticket (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_support_ticket_domain
  ON support_ticket (domain, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_ticket_sla_first_response
  ON support_ticket (sla_first_response_due_at)
  WHERE first_response_at IS NULL AND status NOT IN ('RESOLVED','CLOSED');
CREATE INDEX IF NOT EXISTS idx_support_ticket_sla_resolution
  ON support_ticket (sla_resolution_due_at)
  WHERE resolved_at IS NULL AND status NOT IN ('RESOLVED','CLOSED');

-- الرسائل: تفصل الملاحظة الداخلية عن الرسالة التي يراها المستخدم.
CREATE TABLE IF NOT EXISTS support_ticket_message (
  id               BIGSERIAL PRIMARY KEY,
  ticket_id        BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  author_user_id   BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  author_role      VARCHAR(24) NOT NULL,
  is_internal      BOOLEAN NOT NULL DEFAULT FALSE,
  body             TEXT NOT NULL,
  attachments_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_message_ticket
  ON support_ticket_message (ticket_id, created_at ASC);

-- Internal notes are separate from customer-visible messages.
CREATE TABLE IF NOT EXISTS support_ticket_internal_note (
  id               BIGSERIAL PRIMARY KEY,
  ticket_id        BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  author_user_id   BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  author_role      VARCHAR(24) NOT NULL,
  body             TEXT NOT NULL,
  attachments_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_internal_note_ticket
  ON support_ticket_internal_note (ticket_id, created_at ASC);

-- Assignment history. The current assignment is mirrored on support_ticket for fast filters.
CREATE TABLE IF NOT EXISTS support_ticket_assignment (
  id                  BIGSERIAL PRIMARY KEY,
  ticket_id           BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  assigned_user_id    BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  team                VARCHAR(48),
  assigned_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  action              VARCHAR(24) NOT NULL DEFAULT 'assigned',
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_support_ticket_assignment_action
    CHECK (action IN ('assigned','unassigned','reassigned','team_changed'))
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_assignment_ticket
  ON support_ticket_assignment (ticket_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_ticket_assignment_user
  ON support_ticket_assignment (assigned_user_id, active, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_support_ticket_assignment_one_active
  ON support_ticket_assignment (ticket_id)
  WHERE active = TRUE;

-- Polymorphic links to orders, invoices, taxi rides, services, real-estate, cars, jobs, or community entities.
CREATE TABLE IF NOT EXISTS support_ticket_link (
  id                BIGSERIAL PRIMARY KEY,
  ticket_id         BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  entity_type       VARCHAR(48) NOT NULL,
  entity_id         BIGINT NOT NULL,
  label             VARCHAR(180),
  linked_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reason            TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ticket_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_link_ticket
  ON support_ticket_link (ticket_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_ticket_link_entity
  ON support_ticket_link (entity_type, entity_id);

-- Attachments can belong to a visible message, an internal note, or directly to the ticket.
CREATE TABLE IF NOT EXISTS support_ticket_attachment (
  id                 BIGSERIAL PRIMARY KEY,
  ticket_id          BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  message_id         BIGINT REFERENCES support_ticket_message(id) ON DELETE CASCADE,
  internal_note_id   BIGINT REFERENCES support_ticket_internal_note(id) ON DELETE CASCADE,
  uploaded_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  visibility         VARCHAR(16) NOT NULL DEFAULT 'customer',
  file_url           TEXT NOT NULL,
  storage_key        TEXT,
  file_name          VARCHAR(240),
  mime_type          VARCHAR(120),
  file_size_bytes    BIGINT CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
  metadata_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_support_ticket_attachment_visibility
    CHECK (visibility IN ('customer','internal')),
  CONSTRAINT chk_support_ticket_attachment_parent
    CHECK (
      (message_id IS NOT NULL AND internal_note_id IS NULL)
      OR (message_id IS NULL AND internal_note_id IS NOT NULL)
      OR (message_id IS NULL AND internal_note_id IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_attachment_ticket
  ON support_ticket_attachment (ticket_id, visibility, created_at DESC);

-- الخط الزمني غير القابل للتلاعب (كل انتقال/إجراء).
CREATE TABLE IF NOT EXISTS support_ticket_event (
  id             BIGSERIAL PRIMARY KEY,
  ticket_id      BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE CASCADE,
  actor_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role     VARCHAR(24),
  event_type     VARCHAR(48) NOT NULL,
  from_status    VARCHAR(28),
  to_status      VARCHAR(28),
  metadata       JSONB,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_event_ticket
  ON support_ticket_event (ticket_id, created_at ASC);

COMMIT;
