ALTER TABLE merchant_attendance_log
  ADD COLUMN IF NOT EXISTS check_in_image_url TEXT,
  ADD COLUMN IF NOT EXISTS check_out_image_url TEXT;

CREATE TABLE IF NOT EXISTS merchant_advance_request (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  requested_amount NUMERIC(12,2) NOT NULL CHECK (requested_amount > 0),
  currency VARCHAR(10) NOT NULL DEFAULT 'IQD',
  reason TEXT,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  decided_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  decided_at TIMESTAMPTZ,
  decision_note TEXT,
  linked_salary_action_id BIGINT REFERENCES merchant_salary_action(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_advance_request_scope
  ON merchant_advance_request (merchant_id, status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_advance_request_employee
  ON merchant_advance_request (employee_user_id, status, created_at DESC, id DESC);
