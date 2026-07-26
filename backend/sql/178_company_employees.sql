-- 178_company_employees.sql
-- المرحلة 6: إدارة موظفي مسلكي (الشركة) — منفصلة عن موظفي المتاجر (merchant_*).
-- + عزل هوية الموظف الإدارية عن المجتمع عبر is_internal_staff (يُفرض في Backend).
-- Forward-only.

BEGIN;

ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS is_internal_staff BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_app_user_internal_staff
  ON app_user (is_internal_staff) WHERE is_internal_staff = TRUE;

CREATE TABLE IF NOT EXISTS company_employee_profile (
  id                 BIGSERIAL PRIMARY KEY,
  user_id            BIGINT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
  department         VARCHAR(32) NOT NULL,
  job_title          VARCHAR(120),
  employment_type    VARCHAR(24) NOT NULL DEFAULT 'full_time',
  manager_user_id    BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  status             VARCHAR(16) NOT NULL DEFAULT 'active',
  start_date         DATE,
  base_salary_iqd    INTEGER CHECK (base_salary_iqd IS NULL OR base_salary_iqd >= 0),
  notes              TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_company_employee_department CHECK (department IN (
    'delivery','customer_service','hr','monitoring','accounting',
    'marketing','management','tech','other'
  )),
  CONSTRAINT chk_company_employee_employment CHECK (employment_type IN (
    'full_time','part_time','contract','temporary'
  )),
  CONSTRAINT chk_company_employee_status CHECK (status IN (
    'active','suspended','terminated'
  ))
);

CREATE INDEX IF NOT EXISTS idx_company_employee_department
  ON company_employee_profile (department, status);

-- سجل تغييرات راتب الموظف بتاريخ سريان (لا يُستبدل التاريخ القديم).
CREATE TABLE IF NOT EXISTS company_salary_contract (
  id                 BIGSERIAL PRIMARY KEY,
  employee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  base_salary_iqd    INTEGER NOT NULL CHECK (base_salary_iqd >= 0),
  effective_from     DATE NOT NULL,
  reason             TEXT,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_salary_contract_employee
  ON company_salary_contract (employee_user_id, effective_from DESC);

COMMIT;
