CREATE TABLE IF NOT EXISTS user_residence_info (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  document_type VARCHAR(40) NOT NULL DEFAULT 'residence_card',
  full_name VARCHAR(180),
  town VARCHAR(16),
  building_number VARCHAR(24),
  issue_date DATE,
  contract_number VARCHAR(40),
  floor_number VARCHAR(24),
  apartment_number VARCHAR(24),
  visible_id_number VARCHAR(40),
  image_url TEXT,
  extraction_confidence NUMERIC(5,4) NOT NULL DEFAULT 0,
  extracted_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_residence_info_user_id
  ON user_residence_info(user_id);

CREATE INDEX IF NOT EXISTS idx_user_residence_info_document_type
  ON user_residence_info(document_type);
