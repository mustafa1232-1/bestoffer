BEGIN;

CREATE TABLE IF NOT EXISTS paid_upgrade_plan (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(80) NOT NULL UNIQUE,
  title VARCHAR(180) NOT NULL,
  description TEXT,
  monthly_fee_iqd NUMERIC(12,2) NOT NULL,
  currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  badge_label VARCHAR(80),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT paid_upgrade_plan_fee_check CHECK (monthly_fee_iqd >= 0)
);

CREATE TABLE IF NOT EXISTS paid_upgrade_request (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES paid_upgrade_plan(id) ON DELETE CASCADE,
  status VARCHAR(40) NOT NULL DEFAULT 'pending_admin_review',
  activity_name VARCHAR(180),
  activity_description TEXT,
  contact_phone VARCHAR(32),
  notes TEXT,
  request_meta_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  monthly_fee_iqd NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  review_note TEXT,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  activated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  activated_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT paid_upgrade_request_status_check
    CHECK (
      status IN (
        'pending_admin_review',
        'approved',
        'rejected',
        'activated',
        'cancelled'
      )
    )
);

CREATE TABLE IF NOT EXISTS paid_upgrade_subscription (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES paid_upgrade_plan(id) ON DELETE CASCADE,
  request_id BIGINT UNIQUE REFERENCES paid_upgrade_request(id) ON DELETE SET NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  activated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  expired_at TIMESTAMPTZ,
  last_expiry_reminder_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT paid_upgrade_subscription_status_check
    CHECK (status IN ('active', 'expired')),
  CONSTRAINT paid_upgrade_subscription_dates_check
    CHECK (expires_at > started_at)
);

CREATE TABLE IF NOT EXISTS paid_upgrade_audit (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT REFERENCES paid_upgrade_request(id) ON DELETE CASCADE,
  subscription_id BIGINT REFERENCES paid_upgrade_subscription(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  action_key VARCHAR(64) NOT NULL,
  note TEXT,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_paid_upgrade_request_pending_unique
  ON paid_upgrade_request(user_id, plan_id)
  WHERE status = 'pending_admin_review';

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_request_user_recent
  ON paid_upgrade_request(user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_request_plan_status
  ON paid_upgrade_request(plan_id, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_request_status_recent
  ON paid_upgrade_request(status, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_paid_upgrade_subscription_active_unique
  ON paid_upgrade_subscription(user_id, plan_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_subscription_user_status
  ON paid_upgrade_subscription(user_id, status, expires_at ASC, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_subscription_plan_status
  ON paid_upgrade_subscription(plan_id, status, expires_at ASC, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_audit_request
  ON paid_upgrade_audit(request_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_audit_subscription
  ON paid_upgrade_audit(subscription_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_paid_upgrade_audit_actor
  ON paid_upgrade_audit(actor_user_id, id DESC);

DROP TRIGGER IF EXISTS trg_paid_upgrade_plan_updated ON paid_upgrade_plan;
CREATE TRIGGER trg_paid_upgrade_plan_updated
BEFORE UPDATE ON paid_upgrade_plan
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_paid_upgrade_request_updated ON paid_upgrade_request;
CREATE TRIGGER trg_paid_upgrade_request_updated
BEFORE UPDATE ON paid_upgrade_request
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_paid_upgrade_subscription_updated ON paid_upgrade_subscription;
CREATE TRIGGER trg_paid_upgrade_subscription_updated
BEFORE UPDATE ON paid_upgrade_subscription
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

INSERT INTO paid_upgrade_plan (code, title, description, monthly_fee_iqd, currency, badge_label, is_active, sort_order)
VALUES
  (
    'car_seller_monthly',
    'بائع سيارات شهري',
    'صلاحية نشر وإدارة إعلانات سوق السيارات.',
    75000,
    'IQD',
    'Cars Seller',
    TRUE,
    10
  ),
  (
    'property_seller_monthly',
    'بائع شقق / مؤجر شهري',
    'صلاحية نشر وإدارة إعلانات العقارات.',
    150000,
    'IQD',
    'Real Estate Seller',
    TRUE,
    20
  ),
  (
    'premium_monthly',
    'بريميوم شهري',
    'شارة حساب مميز وصفحة نشاط موسعة وCTA داخلية.',
    200000,
    'IQD',
    'Premium',
    TRUE,
    30
  )
ON CONFLICT (code)
DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  monthly_fee_iqd = EXCLUDED.monthly_fee_iqd,
  currency = EXCLUDED.currency,
  badge_label = EXCLUDED.badge_label,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();

COMMIT;
