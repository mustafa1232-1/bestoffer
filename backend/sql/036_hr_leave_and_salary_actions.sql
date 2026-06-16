CREATE TABLE IF NOT EXISTS merchant_leave_request (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  leave_type VARCHAR(24) NOT NULL DEFAULT 'annual',
  pay_policy VARCHAR(24) NOT NULL DEFAULT 'paid',
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  days_count NUMERIC(6,2) NOT NULL DEFAULT 1 CHECK (days_count > 0),
  reason TEXT,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  decided_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  decided_at TIMESTAMPTZ,
  decision_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (leave_type IN ('annual', 'sick', 'emergency', 'maternity', 'other')),
  CHECK (pay_policy IN ('paid', 'half_paid', 'unpaid', 'sick_paid')),
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  CHECK (date_to >= date_from)
);

CREATE INDEX IF NOT EXISTS idx_merchant_leave_request_scope
  ON merchant_leave_request (merchant_id, status, date_from DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_leave_request_employee
  ON merchant_leave_request (employee_user_id, status, date_from DESC, id DESC);

CREATE TABLE IF NOT EXISTS merchant_salary_action (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  action_type VARCHAR(24) NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount > 0),
  currency VARCHAR(10) NOT NULL DEFAULT 'IQD',
  effective_year INTEGER NOT NULL CHECK (effective_year BETWEEN 2000 AND 2100),
  effective_month INTEGER NOT NULL CHECK (effective_month BETWEEN 1 AND 12),
  description TEXT,
  status VARCHAR(24) NOT NULL DEFAULT 'active',
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  applied_batch_id BIGINT REFERENCES merchant_payroll_batch(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (action_type IN ('bonus', 'allowance', 'deduction', 'advance')),
  CHECK (status IN ('active', 'applied', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_salary_action_scope
  ON merchant_salary_action (
    merchant_id,
    effective_year,
    effective_month,
    status,
    action_type,
    id DESC
  );

CREATE INDEX IF NOT EXISTS idx_merchant_salary_action_employee
  ON merchant_salary_action (
    employee_user_id,
    effective_year,
    effective_month,
    status,
    id DESC
  );
