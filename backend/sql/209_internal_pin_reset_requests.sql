ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS must_change_pin BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS internal_pin_reset_request (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  rejection_reason TEXT,
  approved_temporary_pin_set_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_internal_pin_reset_pending_user
  ON internal_pin_reset_request(user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_internal_pin_reset_status_requested
  ON internal_pin_reset_request(status, requested_at DESC);
