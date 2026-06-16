BEGIN;

CREATE TABLE IF NOT EXISTS order_chat_message (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  sender_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  sender_role VARCHAR(30) NOT NULL,
  message_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_chat_message_order_created
ON order_chat_message(order_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_order_chat_message_sender_created
ON order_chat_message(sender_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS courier_order_cancel_request (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'courier_order_cancel_request_status_check'
  ) THEN
    ALTER TABLE courier_order_cancel_request
      ADD CONSTRAINT courier_order_cancel_request_status_check
      CHECK (status IN ('pending','approved','rejected','cancelled'));
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_courier_order_cancel_request_pending
ON courier_order_cancel_request(order_id)
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_courier_order_cancel_request_courier
ON courier_order_cancel_request(courier_user_id, status, requested_at DESC);

COMMIT;
