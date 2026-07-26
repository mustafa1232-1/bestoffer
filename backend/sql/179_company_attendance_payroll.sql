-- 179_company_attendance_payroll.sql
-- المرحلة 7: حضور موظفي الشركة + المصاريف + دورة الرواتب (DRAFT→ARCHIVED).
-- التوقيت من الخادم (Asia/Baghdad). Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS company_attendance (
  id                 BIGSERIAL PRIMARY KEY,
  employee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  check_in_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  check_out_at       TIMESTAMPTZ,
  source             VARCHAR(24) NOT NULL DEFAULT 'self',
  note               TEXT,
  corrected_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  correction_reason  TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (check_out_at IS NULL OR check_out_at >= check_in_at)
);

-- جلسة حضور مفتوحة واحدة كحد أقصى لكل موظف (منع تسجيل حضور مزدوج).
CREATE UNIQUE INDEX IF NOT EXISTS uq_company_attendance_open
  ON company_attendance (employee_user_id)
  WHERE check_out_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_company_attendance_employee
  ON company_attendance (employee_user_id, check_in_at DESC);

CREATE TABLE IF NOT EXISTS company_expense_claim (
  id                 BIGSERIAL PRIMARY KEY,
  employee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  category           VARCHAR(24) NOT NULL,
  amount_iqd         INTEGER NOT NULL CHECK (amount_iqd >= 0),
  expense_date       DATE NOT NULL DEFAULT CURRENT_DATE,
  reason             TEXT,
  receipt_url        TEXT,
  status             VARCHAR(24) NOT NULL DEFAULT 'submitted',
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at        TIMESTAMPTZ,
  payroll_run_id     BIGINT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_company_expense_category CHECK (category IN (
    'food','transport','communication','work_task','other'
  )),
  CONSTRAINT chk_company_expense_status CHECK (status IN (
    'submitted','approved','rejected','included_in_payroll'
  ))
);

CREATE INDEX IF NOT EXISTS idx_company_expense_employee
  ON company_expense_claim (employee_user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS company_payroll_run (
  id                 BIGSERIAL PRIMARY KEY,
  period_month       VARCHAR(7) NOT NULL,           -- YYYY-MM
  status             VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
  notes              TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  submitted_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_by_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  released_by_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  paid_by_user_id      BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  calculated_at      TIMESTAMPTZ,
  approved_at        TIMESTAMPTZ,
  released_at        TIMESTAMPTZ,
  paid_at            TIMESTAMPTZ,
  archived_at        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_company_payroll_status CHECK (status IN (
    'DRAFT','CALCULATED','UNDER_REVIEW','APPROVED','RELEASED','PAID',
    'ACKNOWLEDGED','ARCHIVED'
  )),
  UNIQUE (period_month)
);

CREATE TABLE IF NOT EXISTS company_payroll_item (
  id                 BIGSERIAL PRIMARY KEY,
  run_id             BIGINT NOT NULL REFERENCES company_payroll_run(id) ON DELETE CASCADE,
  employee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  base_salary_iqd    INTEGER NOT NULL DEFAULT 0,
  additions_iqd      INTEGER NOT NULL DEFAULT 0,
  deductions_iqd     INTEGER NOT NULL DEFAULT 0,
  net_iqd            INTEGER NOT NULL DEFAULT 0,
  breakdown          JSONB NOT NULL DEFAULT '{}'::jsonb,
  acknowledged_at    TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (run_id, employee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_company_payroll_item_run
  ON company_payroll_item (run_id);
CREATE INDEX IF NOT EXISTS idx_company_payroll_item_employee
  ON company_payroll_item (employee_user_id, created_at DESC);

COMMIT;
