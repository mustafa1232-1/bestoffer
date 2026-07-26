-- Phase 4B: audited support-ticket order amendment workflow.

BEGIN;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS order_revision_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS last_order_revision_id BIGINT,
  ADD COLUMN IF NOT EXISTS last_order_revision_applied_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS order_revision (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  support_ticket_id BIGINT NOT NULL REFERENCES support_ticket(id) ON DELETE RESTRICT,
  version_number INTEGER NOT NULL,
  base_order_version INTEGER NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'DRAFT',
  reason TEXT NOT NULL,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_by_employee_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  original_totals_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  proposed_totals_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  original_items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  proposed_items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  price_difference NUMERIC(12,2) NOT NULL DEFAULT 0,
  inventory_effect_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  approvals_required_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  approval_state_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  payment_effect_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submitted_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  applied_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT,
  CONSTRAINT chk_order_revision_status CHECK (status IN (
    'DRAFT',
    'AWAITING_CUSTOMER',
    'AWAITING_MERCHANT',
    'AWAITING_BOTH',
    'APPROVED',
    'APPLYING',
    'APPLIED',
    'REJECTED',
    'CANCELLED',
    'EXPIRED',
    'FAILED'
  )),
  CONSTRAINT chk_order_revision_price_difference
    CHECK (price_difference = ROUND(price_difference, 2)),
  UNIQUE (order_id, version_number)
);

ALTER TABLE customer_order
  DROP CONSTRAINT IF EXISTS customer_order_last_order_revision_fk;
ALTER TABLE customer_order
  ADD CONSTRAINT customer_order_last_order_revision_fk
  FOREIGN KEY (last_order_revision_id)
  REFERENCES order_revision(id)
  ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_order_revision_one_open_per_order
  ON order_revision(order_id)
  WHERE status IN (
    'DRAFT',
    'AWAITING_CUSTOMER',
    'AWAITING_MERCHANT',
    'AWAITING_BOTH',
    'APPROVED',
    'APPLYING'
  );

CREATE INDEX IF NOT EXISTS idx_order_revision_ticket
  ON order_revision(support_ticket_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_revision_order
  ON order_revision(order_id, created_at DESC);

CREATE TABLE IF NOT EXISTS order_revision_item (
  id BIGSERIAL PRIMARY KEY,
  revision_id BIGINT NOT NULL REFERENCES order_revision(id) ON DELETE CASCADE,
  order_item_id BIGINT REFERENCES order_item(id) ON DELETE SET NULL,
  action VARCHAR(24) NOT NULL,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE RESTRICT,
  variant_id BIGINT REFERENCES product_variant(id) ON DELETE SET NULL,
  product_name VARCHAR(150) NOT NULL,
  quantity_before INTEGER NOT NULL DEFAULT 0,
  quantity_after INTEGER NOT NULL DEFAULT 0,
  unit_price_before NUMERIC(12,2) NOT NULL DEFAULT 0,
  unit_price_after NUMERIC(12,2) NOT NULL DEFAULT 0,
  line_total_before NUMERIC(12,2) NOT NULL DEFAULT 0,
  line_total_after NUMERIC(12,2) NOT NULL DEFAULT 0,
  before_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  after_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  inventory_delta INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_order_revision_item_action
    CHECK (action IN ('unchanged','quantity_changed','removed','added','variant_changed','replaced'))
);

CREATE INDEX IF NOT EXISTS idx_order_revision_item_revision
  ON order_revision_item(revision_id, id);

CREATE TABLE IF NOT EXISTS order_revision_approval (
  id BIGSERIAL PRIMARY KEY,
  revision_id BIGINT NOT NULL REFERENCES order_revision(id) ON DELETE CASCADE,
  approval_type VARCHAR(24) NOT NULL,
  approver_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'PENDING',
  decision_note TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at TIMESTAMPTZ,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (revision_id, approval_type),
  CONSTRAINT chk_order_revision_approval_type
    CHECK (approval_type IN ('CUSTOMER','MERCHANT','FINANCE')),
  CONSTRAINT chk_order_revision_approval_status
    CHECK (status IN ('PENDING','APPROVED','REJECTED','EXPIRED','CANCELLED'))
);

CREATE INDEX IF NOT EXISTS idx_order_revision_approval_revision
  ON order_revision_approval(revision_id, approval_type, status);

CREATE TABLE IF NOT EXISTS order_revision_event (
  id BIGSERIAL PRIMARY KEY,
  revision_id BIGINT NOT NULL REFERENCES order_revision(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  support_ticket_id BIGINT REFERENCES support_ticket(id) ON DELETE SET NULL,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_role VARCHAR(40),
  event_type VARCHAR(64) NOT NULL,
  from_status VARCHAR(32),
  to_status VARCHAR(32),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_revision_event_revision
  ON order_revision_event(revision_id, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS order_revision_financial_adjustment (
  id BIGSERIAL PRIMARY KEY,
  revision_id BIGINT NOT NULL REFERENCES order_revision(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  adjustment_type VARCHAR(32) NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  direction VARCHAR(16) NOT NULL,
  payment_method VARCHAR(40),
  status VARCHAR(24) NOT NULL DEFAULT 'RECORDED',
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_order_revision_financial_adjustment_type
    CHECK (adjustment_type IN ('NO_CHANGE','COLLECT_MORE','REFUND','CREDIT')),
  CONSTRAINT chk_order_revision_financial_adjustment_direction
    CHECK (direction IN ('none','customer_owes','customer_credit')),
  CONSTRAINT chk_order_revision_financial_adjustment_status
    CHECK (status IN ('PENDING','RECORDED','SETTLED','FAILED','CANCELLED'))
);

CREATE INDEX IF NOT EXISTS idx_order_revision_financial_adjustment_revision
  ON order_revision_financial_adjustment(revision_id, created_at DESC);

COMMIT;
