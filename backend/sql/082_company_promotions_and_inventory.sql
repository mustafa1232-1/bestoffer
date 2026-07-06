BEGIN;

ALTER TABLE coupon
  ADD COLUMN IF NOT EXISTS scope_kind VARCHAR(20) NOT NULL DEFAULT 'merchant',
  ADD COLUMN IF NOT EXISTS company_id BIGINT REFERENCES company(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS company_applies_to_all_branches BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'coupon_scope_kind_check'
  ) THEN
    ALTER TABLE coupon
      ADD CONSTRAINT coupon_scope_kind_check
      CHECK (scope_kind IN ('global', 'merchant', 'company'));
  END IF;
END
$$;

UPDATE coupon
SET scope_kind = CASE
  WHEN company_id IS NOT NULL THEN 'company'
  WHEN merchant_id IS NOT NULL THEN 'merchant'
  ELSE 'global'
END;

CREATE INDEX IF NOT EXISTS idx_coupon_scope_company
ON coupon(scope_kind, company_id, is_active, created_at DESC);

CREATE TABLE IF NOT EXISTS company_coupon_target (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES coupon(id) ON DELETE CASCADE,
  company_id BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(coupon_id, merchant_id)
);

CREATE INDEX IF NOT EXISTS idx_company_coupon_target_company
ON company_coupon_target(company_id, merchant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS company_campaign (
  id BIGSERIAL PRIMARY KEY,
  company_id BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
  title VARCHAR(160) NOT NULL,
  description VARCHAR(600),
  offer_type VARCHAR(32) NOT NULL CHECK (offer_type IN ('percentage', 'fixed_amount', 'buy_x_get_y')),
  discount_value NUMERIC(12,2),
  buy_quantity INT,
  get_quantity INT,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  status VARCHAR(24) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'active', 'disabled', 'expired')),
  applies_to_all_branches BOOLEAN NOT NULL DEFAULT FALSE,
  max_usage INT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT company_campaign_discount_rules CHECK (
    (offer_type = 'percentage' AND discount_value IS NOT NULL AND discount_value > 0 AND discount_value <= 100 AND buy_quantity IS NULL AND get_quantity IS NULL)
    OR (offer_type = 'fixed_amount' AND discount_value IS NOT NULL AND discount_value > 0 AND buy_quantity IS NULL AND get_quantity IS NULL)
    OR (offer_type = 'buy_x_get_y' AND discount_value IS NULL AND buy_quantity IS NOT NULL AND buy_quantity > 0 AND get_quantity IS NOT NULL AND get_quantity > 0)
  ),
  CONSTRAINT company_campaign_usage_limit CHECK (max_usage IS NULL OR max_usage > 0),
  CONSTRAINT company_campaign_dates CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at)
);

CREATE TABLE IF NOT EXISTS company_campaign_target (
  id BIGSERIAL PRIMARY KEY,
  company_campaign_id BIGINT NOT NULL REFERENCES company_campaign(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_campaign_id, merchant_id)
);

ALTER TABLE merchant_offer
  ADD COLUMN IF NOT EXISTS company_campaign_id BIGINT REFERENCES company_campaign(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_offer_company_campaign
ON merchant_offer(company_campaign_id, merchant_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS inventory_settings (
  merchant_id BIGINT PRIMARY KEY REFERENCES merchant(id) ON DELETE CASCADE,
  company_id BIGINT REFERENCES company(id) ON DELETE SET NULL,
  inventory_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  daily_update_mode VARCHAR(30) NOT NULL DEFAULT 'manual_override'
    CHECK (daily_update_mode IN ('strict_daily', 'soft_reminder', 'manual_override')),
  low_stock_threshold INT NOT NULL DEFAULT 5,
  auto_disable_out_of_stock BOOLEAN NOT NULL DEFAULT TRUE,
  show_all_without_auto_disable BOOLEAN NOT NULL DEFAULT FALSE,
  last_daily_check_at TIMESTAMPTZ,
  last_stock_update_at TIMESTAMPTZ,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_settings_company
ON inventory_settings(company_id, inventory_enabled, updated_at DESC);

CREATE TABLE IF NOT EXISTS store_inventory_item (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  quantity INT NOT NULL DEFAULT 0,
  stock_status VARCHAR(24) NOT NULL DEFAULT 'in_stock'
    CHECK (stock_status IN ('in_stock', 'low_stock', 'out_of_stock', 'manual_disabled')),
  reorder_threshold INT,
  manual_disabled BOOLEAN NOT NULL DEFAULT FALSE,
  auto_disabled BOOLEAN NOT NULL DEFAULT FALSE,
  last_quantity_update_at TIMESTAMPTZ,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(merchant_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_store_inventory_item_merchant_status
ON store_inventory_item(merchant_id, stock_status, updated_at DESC);

CREATE TABLE IF NOT EXISTS inventory_daily_check (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  check_date DATE NOT NULL,
  confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  mode_at_check VARCHAR(30) NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(merchant_id, check_date)
);

CREATE INDEX IF NOT EXISTS idx_inventory_daily_check_merchant_date
ON inventory_daily_check(merchant_id, check_date DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS inventory_audit_log (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES product(id) ON DELETE SET NULL,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_context VARCHAR(40) NOT NULL,
  action_key VARCHAR(120) NOT NULL,
  summary TEXT NOT NULL,
  old_value JSONB NOT NULL DEFAULT '{}'::jsonb,
  new_value JSONB NOT NULL DEFAULT '{}'::jsonb,
  actor_role VARCHAR(40),
  variant_id BIGINT,
  reason TEXT,
  unavailable_until TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_audit_log_merchant
ON inventory_audit_log(merchant_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION set_company_inventory_updated_at()
RETURNS TRIGGER AS $company_inventory_updated$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$company_inventory_updated$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_company_campaign_updated_at ON company_campaign;
CREATE TRIGGER trg_company_campaign_updated_at
BEFORE UPDATE ON company_campaign
FOR EACH ROW
EXECUTE FUNCTION set_company_inventory_updated_at();

DROP TRIGGER IF EXISTS trg_inventory_settings_updated_at ON inventory_settings;
CREATE TRIGGER trg_inventory_settings_updated_at
BEFORE UPDATE ON inventory_settings
FOR EACH ROW
EXECUTE FUNCTION set_company_inventory_updated_at();

DROP TRIGGER IF EXISTS trg_store_inventory_item_updated_at ON store_inventory_item;
CREATE TRIGGER trg_store_inventory_item_updated_at
BEFORE UPDATE ON store_inventory_item
FOR EACH ROW
EXECUTE FUNCTION set_company_inventory_updated_at();

DROP TRIGGER IF EXISTS trg_inventory_daily_check_updated_at ON inventory_daily_check;
CREATE TRIGGER trg_inventory_daily_check_updated_at
BEFORE UPDATE ON inventory_daily_check
FOR EACH ROW
EXECUTE FUNCTION set_company_inventory_updated_at();

COMMIT;
