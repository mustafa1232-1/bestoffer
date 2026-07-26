-- 180_employee_evaluation.sql
-- المرحلة 5: تقييم الموظفين. المقاييس تُحسب من التذاكر والحضور (لا جداول
-- مكرّرة)؛ هذا الجدول لملاحظة المشرف + اعتراض الموظف فقط. Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS company_employee_review (
  id                 BIGSERIAL PRIMARY KEY,
  employee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  period             VARCHAR(7) NOT NULL,          -- YYYY-MM
  supervisor_rating  SMALLINT CHECK (supervisor_rating IS NULL OR (supervisor_rating BETWEEN 1 AND 5)),
  supervisor_note    TEXT,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  objection_text     TEXT,
  objection_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (employee_user_id, period)
);

CREATE INDEX IF NOT EXISTS idx_company_employee_review_employee
  ON company_employee_review (employee_user_id, period DESC);

COMMIT;
