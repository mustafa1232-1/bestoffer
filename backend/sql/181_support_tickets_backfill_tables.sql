-- 181_support_tickets_backfill_tables.sql
-- تصحيح hygiene: migration 172 عُدِّل بعد تطبيقه فأُضيفت جداول داخل نفس الملف،
-- لذا القواعد التي طبّقت 172 القديم تفتقد هذه الجداول (المُشغِّل يتتبع بالاسم).
-- هذا migration يضمن وجودها بأمان (IF NOT EXISTS) على كل البيئات. Forward-only.

BEGIN;

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

COMMIT;
