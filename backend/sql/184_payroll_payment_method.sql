-- 184_payroll_payment_method.sql
-- طريقة دفع الرواتب: تُسجَّل عند وضع الدورة PAID. Forward-only.

BEGIN;

ALTER TABLE company_payroll_run
  ADD COLUMN IF NOT EXISTS payment_method    VARCHAR(24),
  ADD COLUMN IF NOT EXISTS payment_reference VARCHAR(160);

ALTER TABLE company_payroll_run
  DROP CONSTRAINT IF EXISTS chk_company_payroll_payment_method;
ALTER TABLE company_payroll_run
  ADD CONSTRAINT chk_company_payroll_payment_method
  CHECK (
    payment_method IS NULL
    OR payment_method IN ('cash', 'bank_transfer', 'wallet', 'card', 'other')
  );

COMMIT;
