CREATE TABLE IF NOT EXISTS app_section_availability (
  id BIGSERIAL PRIMARY KEY,
  section_key VARCHAR(64) NOT NULL,
  display_name VARCHAR(120) NOT NULL,
  parent_section_key VARCHAR(64),
  surface_scope VARCHAR(32) NOT NULL DEFAULT 'user',
  status VARCHAR(32) NOT NULL DEFAULT 'open',
  is_visible BOOLEAN NOT NULL DEFAULT TRUE,
  user_message TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  allow_existing_active_access BOOLEAN NOT NULL DEFAULT TRUE,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_app_section_availability_status
    CHECK (status IN ('open', 'coming_soon', 'maintenance', 'temporarily_closed')),
  CONSTRAINT uq_app_section_availability_scope_key
    UNIQUE (surface_scope, section_key)
);

CREATE INDEX IF NOT EXISTS idx_app_section_availability_scope_sort
  ON app_section_availability (surface_scope, sort_order, id);

CREATE INDEX IF NOT EXISTS idx_app_section_availability_parent
  ON app_section_availability (surface_scope, parent_section_key, section_key);

CREATE TABLE IF NOT EXISTS app_section_availability_audit (
  id BIGSERIAL PRIMARY KEY,
  section_availability_id BIGINT NOT NULL REFERENCES app_section_availability(id) ON DELETE CASCADE,
  section_key VARCHAR(64) NOT NULL,
  surface_scope VARCHAR(32) NOT NULL,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  from_status VARCHAR(32),
  to_status VARCHAR(32),
  old_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  new_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_section_availability_audit_section_time
  ON app_section_availability_audit (surface_scope, section_key, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION set_app_section_availability_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_app_section_availability_updated
  ON app_section_availability;

CREATE TRIGGER trg_app_section_availability_updated
BEFORE UPDATE ON app_section_availability
FOR EACH ROW
EXECUTE FUNCTION set_app_section_availability_updated_at();

INSERT INTO app_section_availability (
  section_key,
  display_name,
  parent_section_key,
  surface_scope,
  status,
  is_visible,
  user_message,
  sort_order,
  allow_existing_active_access,
  metadata_json
)
VALUES
  ('shopping', 'التسوق', NULL, 'user', 'open', TRUE, NULL, 10, TRUE, '{"module":"shopping"}'::jsonb),
  ('services', 'الخدمات', NULL, 'user', 'open', TRUE, NULL, 20, TRUE, '{"module":"services"}'::jsonb),
  ('taxi', 'التكسي', NULL, 'user', 'open', TRUE, NULL, 30, TRUE, '{"module":"taxi"}'::jsonb),
  ('community', 'المجتمع', NULL, 'user', 'open', TRUE, NULL, 40, TRUE, '{"module":"community"}'::jsonb),
  ('jobs', 'الوظائف', NULL, 'user', 'open', TRUE, NULL, 50, TRUE, '{"module":"jobs"}'::jsonb),
  ('real_estate', 'العقارات', NULL, 'user', 'open', TRUE, NULL, 60, TRUE, '{"module":"real_estate"}'::jsonb),
  ('cars', 'السيارات', NULL, 'user', 'open', TRUE, NULL, 70, TRUE, '{"module":"cars"}'::jsonb),
  ('pharmacy', 'الصيدلية', 'shopping', 'user', 'open', TRUE, NULL, 80, TRUE, '{"module":"pharmacy"}'::jsonb)
ON CONFLICT (surface_scope, section_key) DO NOTHING;
