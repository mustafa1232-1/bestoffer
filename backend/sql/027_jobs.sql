-- ============================================================
-- 027 Jobs module
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS job_post (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(180) NOT NULL,
  company_name VARCHAR(180) NOT NULL,
  company_logo_url TEXT,
  category VARCHAR(120) NOT NULL,
  city VARCHAR(120) NOT NULL,
  area VARCHAR(120),
  workplace_type VARCHAR(20) NOT NULL DEFAULT 'on_site'
    CHECK (workplace_type IN ('on_site', 'hybrid', 'remote')),
  employment_type VARCHAR(20) NOT NULL DEFAULT 'full_time'
    CHECK (employment_type IN ('full_time', 'part_time', 'contract', 'internship', 'freelance')),
  experience_level VARCHAR(20) NOT NULL DEFAULT 'mid'
    CHECK (experience_level IN ('entry', 'junior', 'mid', 'senior', 'lead', 'manager')),
  education_level VARCHAR(80),
  salary_min NUMERIC(12,2),
  salary_max NUMERIC(12,2),
  salary_currency VARCHAR(10) NOT NULL DEFAULT 'IQD',
  salary_period VARCHAR(20) NOT NULL DEFAULT 'monthly'
    CHECK (salary_period IN ('hourly', 'monthly', 'yearly', 'project')),
  salary_is_negotiable BOOLEAN NOT NULL DEFAULT TRUE,
  years_experience_min SMALLINT,
  years_experience_max SMALLINT,
  vacancies INTEGER NOT NULL DEFAULT 1,
  description TEXT NOT NULL,
  requirements TEXT,
  responsibilities TEXT,
  benefits TEXT,
  skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  contact_phone VARCHAR(30),
  contact_email VARCHAR(180),
  apply_url TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('draft', 'active', 'paused', 'closed')),
  is_featured BOOLEAN NOT NULL DEFAULT FALSE,
  published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  created_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_by_role user_role NOT NULL,
  merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT job_post_salary_valid CHECK (
    salary_min IS NULL OR salary_max IS NULL OR salary_max >= salary_min
  ),
  CONSTRAINT job_post_experience_valid CHECK (
    years_experience_min IS NULL OR years_experience_min >= 0
  ),
  CONSTRAINT job_post_experience_max_valid CHECK (
    years_experience_max IS NULL OR years_experience_max >= 0
  ),
  CONSTRAINT job_post_experience_range_valid CHECK (
    years_experience_min IS NULL OR years_experience_max IS NULL
    OR years_experience_max >= years_experience_min
  ),
  CONSTRAINT job_post_vacancies_valid CHECK (vacancies > 0)
);

CREATE TABLE IF NOT EXISTS job_application (
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES job_post(id) ON DELETE CASCADE,
  applicant_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  full_name VARCHAR(180) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  message TEXT,
  resume_url TEXT,
  expected_salary NUMERIC(12,2),
  status VARCHAR(20) NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'shortlisted', 'rejected', 'hired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (job_id, applicant_user_id)
);

CREATE INDEX IF NOT EXISTS idx_job_post_status ON job_post(status);
CREATE INDEX IF NOT EXISTS idx_job_post_created_by ON job_post(created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_job_post_merchant ON job_post(merchant_id);
CREATE INDEX IF NOT EXISTS idx_job_post_city ON job_post(city);
CREATE INDEX IF NOT EXISTS idx_job_post_area ON job_post(area);
CREATE INDEX IF NOT EXISTS idx_job_post_category ON job_post(category);
CREATE INDEX IF NOT EXISTS idx_job_post_published ON job_post(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_post_expires ON job_post(expires_at);
CREATE INDEX IF NOT EXISTS idx_job_post_deleted ON job_post(deleted_at);

CREATE INDEX IF NOT EXISTS idx_job_application_job ON job_application(job_id);
CREATE INDEX IF NOT EXISTS idx_job_application_applicant ON job_application(applicant_user_id);
CREATE INDEX IF NOT EXISTS idx_job_application_status ON job_application(status);

CREATE OR REPLACE FUNCTION set_job_post_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_job_post_updated ON job_post;
CREATE TRIGGER trg_job_post_updated
BEFORE UPDATE ON job_post
FOR EACH ROW
EXECUTE FUNCTION set_job_post_updated_at();

CREATE OR REPLACE FUNCTION set_job_application_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_job_application_updated ON job_application;
CREATE TRIGGER trg_job_application_updated
BEFORE UPDATE ON job_application
FOR EACH ROW
EXECUTE FUNCTION set_job_application_updated_at();

COMMIT;
