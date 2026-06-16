BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'company_portal'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'company_portal';
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS company (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(180) NOT NULL,
  legal_name VARCHAR(220),
  brand_name VARCHAR(220),
  code VARCHAR(40) NOT NULL UNIQUE,
  contact_phone VARCHAR(30),
  contact_email VARCHAR(180),
  logo_url TEXT,
  status VARCHAR(24) NOT NULL DEFAULT 'active'
    CHECK (status IN ('draft', 'active', 'disabled')),
  notes TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_status
ON company(status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS company_user (
  id BIGSERIAL PRIMARY KEY,
  company_id BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role VARCHAR(40) NOT NULL
    CHECK (role IN ('company_owner', 'company_manager', 'finance_viewer', 'operations_viewer')),
  permissions_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  invited_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_company_user_company_role
ON company_user(company_id, role, is_active, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_company_user_user
ON company_user(user_id, is_active, created_at DESC);

CREATE TABLE IF NOT EXISTS company_default_policy (
  company_id BIGINT PRIMARY KEY REFERENCES company(id) ON DELETE CASCADE,
  commission_rate NUMERIC(6,4),
  service_fee_mode VARCHAR(30),
  service_fee_value NUMERIC(12,2),
  delivery_fee_mode VARCHAR(30),
  delivery_fee_value NUMERIC(12,2),
  app_delivery_enabled BOOLEAN,
  merchant_delivery_enabled BOOLEAN,
  settlement_cycle VARCHAR(20),
  inventory_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  inventory_update_mode VARCHAR(30) NOT NULL DEFAULT 'manual_override'
    CHECK (inventory_update_mode IN ('strict_daily', 'soft_reminder', 'manual_override')),
  low_stock_threshold INT NOT NULL DEFAULT 5,
  auto_disable_out_of_stock BOOLEAN NOT NULL DEFAULT TRUE,
  show_all_without_auto_disable BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS company_id BIGINT REFERENCES company(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_company
ON merchant(company_id, is_disabled, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS company_branch_request (
  id BIGSERIAL PRIMARY KEY,
  company_id BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
  requested_name VARCHAR(180) NOT NULL,
  requested_type VARCHAR(40) NOT NULL CHECK (requested_type IN ('restaurant', 'market')),
  requested_description TEXT,
  requested_phone VARCHAR(30),
  requested_image_url TEXT,
  requested_tagline VARCHAR(160),
  requested_working_hours VARCHAR(160),
  requested_service_area_note VARCHAR(240),
  branch_location_label VARCHAR(180),
  proposed_owner_full_name VARCHAR(180),
  proposed_owner_phone VARCHAR(30),
  proposed_owner_pin_hash TEXT,
  proposed_owner_block VARCHAR(20),
  proposed_owner_building_number VARCHAR(20),
  proposed_owner_apartment VARCHAR(20),
  requested_policy_override_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status VARCHAR(30) NOT NULL DEFAULT 'pending_admin_review'
    CHECK (status IN ('pending_admin_review', 'approved', 'rejected', 'cancelled')),
  review_note TEXT,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  approved_merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_branch_request_company_status
ON company_branch_request(company_id, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_company_branch_request_status
ON company_branch_request(status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS company_audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(40),
  action_key VARCHAR(120) NOT NULL,
  summary TEXT NOT NULL,
  target_type VARCHAR(80),
  target_id BIGINT,
  target_label VARCHAR(240),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_audit_log_company
ON company_audit_log(company_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION set_company_updated_at()
RETURNS TRIGGER AS $company_updated$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$company_updated$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_company_updated_at ON company;
CREATE TRIGGER trg_company_updated_at
BEFORE UPDATE ON company
FOR EACH ROW
EXECUTE FUNCTION set_company_updated_at();

DROP TRIGGER IF EXISTS trg_company_user_updated_at ON company_user;
CREATE TRIGGER trg_company_user_updated_at
BEFORE UPDATE ON company_user
FOR EACH ROW
EXECUTE FUNCTION set_company_updated_at();

DROP TRIGGER IF EXISTS trg_company_default_policy_updated_at ON company_default_policy;
CREATE TRIGGER trg_company_default_policy_updated_at
BEFORE UPDATE ON company_default_policy
FOR EACH ROW
EXECUTE FUNCTION set_company_updated_at();

DROP TRIGGER IF EXISTS trg_company_branch_request_updated_at ON company_branch_request;
CREATE TRIGGER trg_company_branch_request_updated_at
BEFORE UPDATE ON company_branch_request
FOR EACH ROW
EXECUTE FUNCTION set_company_updated_at();

COMMIT;
