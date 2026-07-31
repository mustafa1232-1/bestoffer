-- Optional human employee identifier (معرّف الموظف) shown on the employee's HR
-- profile — distinct from the numeric user id and from the login phone.
ALTER TABLE company_employee_profile
  ADD COLUMN IF NOT EXISTS employee_code VARCHAR(40);

CREATE INDEX IF NOT EXISTS idx_company_employee_code
  ON company_employee_profile (employee_code)
  WHERE employee_code IS NOT NULL;
