BEGIN;

ALTER TABLE product
  ADD COLUMN IF NOT EXISTS product_modifier_schema_json JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE order_item
  ADD COLUMN IF NOT EXISTS selected_modifiers_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS modifiers_unit_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS modifiers_line_total NUMERIC(12,2) NOT NULL DEFAULT 0;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS cancelled_by_role VARCHAR(24),
  ADD COLUMN IF NOT EXISTS cancellation_reason_code VARCHAR(64),
  ADD COLUMN IF NOT EXISTS cancellation_reason_text TEXT,
  ADD COLUMN IF NOT EXISTS returned_by_role VARCHAR(24),
  ADD COLUMN IF NOT EXISTS return_reason_code VARCHAR(64),
  ADD COLUMN IF NOT EXISTS return_reason_text TEXT,
  ADD COLUMN IF NOT EXISTS return_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_window_expires_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS order_action_reason_catalog (
  id BIGSERIAL PRIMARY KEY,
  actor_scope VARCHAR(24) NOT NULL,
  action_kind VARCHAR(24) NOT NULL,
  reason_code VARCHAR(64) NOT NULL,
  reason_label_ar VARCHAR(180) NOT NULL,
  reason_label_en VARCHAR(180),
  allows_other_text BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (actor_scope, action_kind, reason_code)
);

CREATE INDEX IF NOT EXISTS idx_order_action_reason_catalog_scope
ON order_action_reason_catalog (actor_scope, action_kind, is_active, sort_order, id);

CREATE OR REPLACE FUNCTION set_order_action_reason_catalog_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_action_reason_catalog_updated ON order_action_reason_catalog;
CREATE TRIGGER trg_order_action_reason_catalog_updated
BEFORE UPDATE ON order_action_reason_catalog
FOR EACH ROW
EXECUTE FUNCTION set_order_action_reason_catalog_updated_at();

CREATE TABLE IF NOT EXISTS order_action_event (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  actor_scope VARCHAR(24) NOT NULL,
  action_kind VARCHAR(24) NOT NULL,
  reason_code VARCHAR(64),
  reason_text TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_action_event_order
ON order_action_event (order_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_action_event_scope
ON order_action_event (actor_scope, action_kind, created_at DESC);

INSERT INTO order_action_reason_catalog
  (actor_scope, action_kind, reason_code, reason_label_ar, reason_label_en, allows_other_text, sort_order)
VALUES
  ('customer', 'cancel', 'changed_mind', 'تغيّرت رغبتي', 'Changed my mind', FALSE, 10),
  ('customer', 'cancel', 'address_issue', 'مشكلة في العنوان', 'Address issue', FALSE, 20),
  ('customer', 'cancel', 'duplicate_order', 'طلب مكرر', 'Duplicate order', FALSE, 30),
  ('customer', 'cancel', 'other', 'سبب آخر', 'Other', TRUE, 90),
  ('customer', 'return', 'wrong_item', 'وصلني منتج مختلف', 'Wrong item', FALSE, 10),
  ('customer', 'return', 'damaged_item', 'المنتج متضرر', 'Damaged item', FALSE, 20),
  ('customer', 'return', 'quality_issue', 'مشكلة جودة', 'Quality issue', FALSE, 30),
  ('customer', 'return', 'other', 'سبب آخر', 'Other', TRUE, 90),
  ('store', 'cancel', 'out_of_stock', 'المنتج غير متوفر', 'Out of stock', FALSE, 10),
  ('store', 'cancel', 'store_closed', 'المتجر مغلق', 'Store is closed', FALSE, 20),
  ('store', 'cancel', 'cannot_prepare', 'تعذر التجهيز', 'Cannot prepare order', FALSE, 30),
  ('store', 'cancel', 'out_of_range', 'العنوان خارج النطاق', 'Out of range', FALSE, 40),
  ('store', 'cancel', 'other', 'سبب آخر', 'Other', TRUE, 90),
  ('courier', 'cancel', 'customer_no_answer', 'العميل لا يرد', 'Customer not answering', FALSE, 10),
  ('courier', 'cancel', 'address_not_found', 'عنوان غير دقيق', 'Address not found', FALSE, 20),
  ('courier', 'cancel', 'pickup_issue', 'تعذر الاستلام من المتجر', 'Pickup issue', FALSE, 30),
  ('courier', 'cancel', 'other', 'سبب آخر', 'Other', TRUE, 90)
ON CONFLICT (actor_scope, action_kind, reason_code) DO NOTHING;

COMMIT;
