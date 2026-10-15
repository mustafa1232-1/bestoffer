BEGIN;

ALTER TABLE service_offerings
  ADD COLUMN IF NOT EXISTS service_key VARCHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_offerings_provider_service_key
  ON service_offerings (provider_id, service_key)
  WHERE service_key IS NOT NULL;

ALTER TABLE service_requests
  ADD COLUMN IF NOT EXISTS service_key VARCHAR(64),
  ADD COLUMN IF NOT EXISTS service_title VARCHAR(180),
  ADD COLUMN IF NOT EXISTS urgency VARCHAR(20) NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS intake_answers JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS routing_status VARCHAR(24) NOT NULL DEFAULT 'new',
  ADD COLUMN IF NOT EXISTS assigned_professional_name VARCHAR(180),
  ADD COLUMN IF NOT EXISTS assigned_professional_phone VARCHAR(32),
  ADD COLUMN IF NOT EXISTS assignment_note TEXT,
  ADD COLUMN IF NOT EXISTS assigned_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS emergency_target VARCHAR(40),
  ADD COLUMN IF NOT EXISTS emergency_contacted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS preferred_contact VARCHAR(20) NOT NULL DEFAULT 'phone';

ALTER TABLE service_requests
  DROP CONSTRAINT IF EXISTS service_requests_urgency_chk,
  DROP CONSTRAINT IF EXISTS service_requests_routing_status_chk,
  DROP CONSTRAINT IF EXISTS service_requests_preferred_contact_chk;

ALTER TABLE service_requests
  ADD CONSTRAINT service_requests_urgency_chk
    CHECK (urgency IN ('normal', 'urgent', 'emergency')),
  ADD CONSTRAINT service_requests_routing_status_chk
    CHECK (routing_status IN ('new', 'triaged', 'assigned', 'contacted', 'en_route', 'resolved', 'cancelled')),
  ADD CONSTRAINT service_requests_preferred_contact_chk
    CHECK (preferred_contact IN ('phone', 'whatsapp', 'in_app'));

CREATE INDEX IF NOT EXISTS idx_service_requests_central_queue
  ON service_requests (urgency, routing_status, created_at DESC)
  WHERE service_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS service_request_assignments (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  professional_name VARCHAR(180),
  professional_phone VARCHAR(32),
  routing_status VARCHAR(24) NOT NULL,
  note TEXT,
  assigned_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_request_assignments_status_chk CHECK (
    routing_status IN ('triaged', 'assigned', 'contacted', 'en_route', 'resolved', 'cancelled')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_request_assignments_request
  ON service_request_assignments (request_id, created_at DESC, id DESC);

COMMIT;
