BEGIN;

ALTER TABLE service_requests
  ADD COLUMN IF NOT EXISTS booking_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS booking_idempotency_key VARCHAR(160),
  ADD COLUMN IF NOT EXISTS booking_pricing_type VARCHAR(40),
  ADD COLUMN IF NOT EXISTS booking_price_version VARCHAR(120),
  ADD COLUMN IF NOT EXISTS booking_unit_price_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS booking_quantity NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS booking_duration_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS booking_subtotal_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS booking_discount_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS booking_service_fee_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS booking_total_iqd NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS booking_promotion_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS booking_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_provider_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_finalization_due_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_finalized_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_transition_note TEXT;

ALTER TABLE service_request_status_history
  ADD COLUMN IF NOT EXISTS booking_version INTEGER,
  ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(160),
  ADD COLUMN IF NOT EXISTS price_version VARCHAR(120),
  ADD COLUMN IF NOT EXISTS booking_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE service_requests
  DROP CONSTRAINT IF EXISTS service_requests_status_chk;

ALTER TABLE service_requests
  ADD CONSTRAINT service_requests_status_chk CHECK (
    status IN (
      'pending',
      'awaiting_provider',
      'accepted',
      'scheduled',
      'in_progress',
      'completed',
      'cancelled',
      'rejected',
      'PENDING_PROVIDER_CONFIRMATION',
      'CONFIRMED',
      'IN_PROGRESS',
      'PROVIDER_COMPLETED',
      'COMPLETED',
      'REJECTED_BY_PROVIDER',
      'CANCELLED_BY_CUSTOMER',
      'CANCELLED_BY_PROVIDER',
      'CANCELLED_BY_ADMIN',
      'EXPIRED',
      'DISPUTED'
    )
  );

ALTER TABLE service_promotions
  DROP CONSTRAINT IF EXISTS service_promotions_type_chk;

ALTER TABLE service_promotions
  ADD CONSTRAINT service_promotions_type_chk CHECK (
    discount_type IN ('percentage', 'fixed', 'special_price', 'PERCENTAGE', 'FIXED_AMOUNT', 'SPECIAL_UNIT_PRICE')
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_requests_booking_create_idempotency
  ON service_requests (customer_user_id, booking_idempotency_key)
  WHERE booking_idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_request_status_history_idempotency
  ON service_request_status_history (request_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_service_requests_booking_finalization_due
  ON service_requests (status, booking_finalization_due_at, updated_at DESC)
  WHERE booking_finalization_due_at IS NOT NULL;

ALTER TABLE notification_outbox
  ADD COLUMN IF NOT EXISTS target_app VARCHAR(40),
  ADD COLUMN IF NOT EXISTS deep_link TEXT;

COMMIT;
