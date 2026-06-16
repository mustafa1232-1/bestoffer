BEGIN;

ALTER TABLE courier_order_cancel_request
  ADD COLUMN IF NOT EXISTS reason_code VARCHAR(64),
  ADD COLUMN IF NOT EXISTS reason_text TEXT;

UPDATE courier_order_cancel_request
SET
  reason_code = COALESCE(NULLIF(TRIM(reason_code), ''), 'other'),
  reason_text = COALESCE(reason_text, NULLIF(TRIM(reason), ''))
WHERE reason_code IS NULL
   OR TRIM(reason_code) = '';

CREATE INDEX IF NOT EXISTS idx_courier_cancel_reason_code
ON courier_order_cancel_request (reason_code, status, requested_at DESC);

INSERT INTO order_action_reason_catalog
  (actor_scope, action_kind, reason_code, reason_label_ar, reason_label_en, allows_other_text, sort_order)
VALUES
  ('customer', 'cancel', 'delay_too_long', 'تأخر الطلب', 'Order delayed too long', FALSE, 25),
  ('customer', 'cancel', 'wrong_address', 'تعديل العنوان', 'Wrong address details', FALSE, 26),
  ('customer', 'return', 'item_damaged', 'المنتج تالف', 'Item damaged', FALSE, 25)
ON CONFLICT (actor_scope, action_kind, reason_code) DO NOTHING;

COMMIT;
