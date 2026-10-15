BEGIN;

ALTER TABLE coupon
  ADD COLUMN IF NOT EXISTS surface_scope VARCHAR(20) NOT NULL DEFAULT 'shopping',
  ADD COLUMN IF NOT EXISTS target_user_id BIGINT REFERENCES app_user(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS popup_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS popup_title VARCHAR(180),
  ADD COLUMN IF NOT EXISTS popup_message TEXT,
  ADD COLUMN IF NOT EXISTS new_customers_only BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE coupon
  DROP CONSTRAINT IF EXISTS coupon_surface_scope_chk;

ALTER TABLE coupon
  ADD CONSTRAINT coupon_surface_scope_chk CHECK (
    surface_scope IN ('shopping', 'taxi', 'services', 'all')
  );

CREATE TABLE IF NOT EXISTS coupon_popup_delivery (
  id BIGSERIAL PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES coupon(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  shown_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_at TIMESTAMPTZ,
  UNIQUE (coupon_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_coupon_popup_delivery_user
  ON coupon_popup_delivery (user_id, acknowledged_at, shown_at DESC);

INSERT INTO coupon (
  code,
  description,
  discount_type,
  discount_value,
  min_order_total,
  max_uses,
  merchant_id,
  scope_kind,
  valid_from,
  is_active,
  surface_scope,
  popup_enabled,
  popup_title,
  popup_message,
  new_customers_only
)
VALUES (
  'MASLAK3',
  'خصم ترحيبي لمستخدمي مسلكي الجدد',
  'percent',
  10,
  0,
  NULL,
  NULL,
  'global',
  NOW(),
  TRUE,
  'shopping',
  TRUE,
  'مرحباً بك في مسلكي',
  'حصلت على خصم 10% لأنك اخترت مسلكي. استخدم الكود مرة واحدة في التسوق.',
  TRUE
)
ON CONFLICT (code) DO UPDATE SET
  description = EXCLUDED.description,
  discount_type = EXCLUDED.discount_type,
  discount_value = EXCLUDED.discount_value,
  min_order_total = EXCLUDED.min_order_total,
  merchant_id = NULL,
  scope_kind = 'global',
  valid_from = EXCLUDED.valid_from,
  is_active = TRUE,
  surface_scope = 'shopping',
  target_user_id = NULL,
  popup_enabled = TRUE,
  popup_title = EXCLUDED.popup_title,
  popup_message = EXCLUDED.popup_message,
  new_customers_only = TRUE;

COMMIT;
