BEGIN;

ALTER TABLE order_action_event
  ADD COLUMN IF NOT EXISTS actor_display_name VARCHAR(180),
  ADD COLUMN IF NOT EXISTS actor_role VARCHAR(40),
  ADD COLUMN IF NOT EXISTS target_scope VARCHAR(40),
  ADD COLUMN IF NOT EXISTS target_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS event_label_ar VARCHAR(240),
  ADD COLUMN IF NOT EXISTS event_label_en VARCHAR(240);

CREATE INDEX IF NOT EXISTS idx_order_action_event_created_desc
ON order_action_event (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_order_action_event_reason
ON order_action_event (action_kind, reason_code, created_at DESC);

COMMIT;
