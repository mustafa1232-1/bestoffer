DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'hr'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'hr';
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS merchant_hr_staff (
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  hr_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  source VARCHAR(20) NOT NULL DEFAULT 'owner',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (merchant_id, hr_user_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_hr_staff_hr
  ON merchant_hr_staff (hr_user_id, is_active, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_hr_staff_merchant
  ON merchant_hr_staff (merchant_id, is_active, updated_at DESC);

CREATE TABLE IF NOT EXISTS merchant_employee_profile (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role_tag VARCHAR(80) NOT NULL DEFAULT 'staff',
  employment_type VARCHAR(32) NOT NULL DEFAULT 'full_time',
  base_salary NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (base_salary >= 0),
  currency VARCHAR(10) NOT NULL DEFAULT 'IQD',
  work_days_per_week SMALLINT NOT NULL DEFAULT 6 CHECK (work_days_per_week BETWEEN 1 AND 7),
  shift_start_time TIME,
  shift_end_time TIME,
  joined_at DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  notes TEXT,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (merchant_id, employee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_employee_profile_merchant
  ON merchant_employee_profile (merchant_id, is_active, role_tag, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_employee_profile_employee
  ON merchant_employee_profile (employee_user_id, is_active, updated_at DESC);

CREATE TABLE IF NOT EXISTS merchant_attendance_log (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,
  check_in_at TIMESTAMPTZ,
  check_out_at TIMESTAMPTZ,
  status VARCHAR(24) NOT NULL DEFAULT 'present',
  source VARCHAR(24) NOT NULL DEFAULT 'manual',
  note TEXT,
  recorded_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (merchant_id, employee_user_id, attendance_date),
  CHECK (status IN ('present', 'absent', 'leave', 'half_day', 'late')),
  CHECK (source IN ('manual', 'self_check_in', 'self_check_out', 'imported'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_attendance_log_merchant_date
  ON merchant_attendance_log (merchant_id, attendance_date DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_attendance_log_employee_date
  ON merchant_attendance_log (employee_user_id, attendance_date DESC, id DESC);

CREATE TABLE IF NOT EXISTS merchant_payroll_batch (
  id BIGSERIAL PRIMARY KEY,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  period_year INTEGER NOT NULL CHECK (period_year BETWEEN 2000 AND 2100),
  period_month INTEGER NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  status VARCHAR(24) NOT NULL DEFAULT 'draft',
  summary_note TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  acknowledged_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  acknowledged_at TIMESTAMPTZ,
  closed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (merchant_id, period_year, period_month),
  CHECK (status IN ('draft', 'submitted', 'processing', 'closed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_payroll_batch_merchant_status
  ON merchant_payroll_batch (merchant_id, status, period_year DESC, period_month DESC, id DESC);

CREATE TABLE IF NOT EXISTS merchant_payroll_item (
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES merchant_payroll_batch(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  employee_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  base_salary NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (base_salary >= 0),
  bonuses NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (bonuses >= 0),
  deductions NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (deductions >= 0),
  leave_adjustment NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_salary NUMERIC(12,2) NOT NULL DEFAULT 0,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  hr_note TEXT,
  payout_note TEXT,
  paid_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (batch_id, employee_user_id),
  CHECK (status IN ('pending', 'paid', 'rejected'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_payroll_item_batch_status
  ON merchant_payroll_item (batch_id, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_payroll_item_employee
  ON merchant_payroll_item (employee_user_id, status, paid_at DESC);
