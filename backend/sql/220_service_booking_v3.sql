BEGIN;

ALTER TABLE service_requests
  ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(32),
  ADD COLUMN IF NOT EXISTS medical_info JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS customer_cancel_available_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invoice_admin_discount_iqd NUMERIC(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS invoice_admin_discount_note TEXT,
  ADD COLUMN IF NOT EXISTS invoice_coupon_id BIGINT REFERENCES coupon(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS invoice_coupon_code VARCHAR(80),
  ADD COLUMN IF NOT EXISTS invoice_coupon_discount_iqd NUMERIC(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS invoice_total_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30) NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS payment_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE service_requests
  DROP CONSTRAINT IF EXISTS service_requests_payment_method_chk;

ALTER TABLE service_requests
  ADD CONSTRAINT service_requests_payment_method_chk CHECK (
    payment_method IN ('cash', 'card', 'wallet', 'bank_transfer')
  );

UPDATE service_requests
SET customer_cancel_available_at = created_at + INTERVAL '15 minutes'
WHERE customer_cancel_available_at IS NULL;

CREATE TABLE IF NOT EXISTS service_request_messages (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  sender_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_request_messages_message_chk CHECK (
    CHAR_LENGTH(BTRIM(message)) BETWEEN 1 AND 2000
  )
);

CREATE INDEX IF NOT EXISTS idx_service_request_messages_request
  ON service_request_messages (request_id, created_at ASC, id ASC);

CREATE INDEX IF NOT EXISTS idx_service_requests_payment_queue
  ON service_requests (payment_submitted_at DESC, updated_at DESC)
  WHERE payment_submitted_at IS NOT NULL AND payment_confirmed_at IS NULL;

ALTER TABLE coupon_redemption
  ADD COLUMN IF NOT EXISTS service_request_id BIGINT REFERENCES service_requests(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_coupon_redemption_service_request
  ON coupon_redemption (service_request_id);

COMMIT;
