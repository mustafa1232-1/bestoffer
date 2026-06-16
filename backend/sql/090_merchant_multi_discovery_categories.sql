BEGIN;

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS discovery_select_all BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS merchant_discovery_subcategory (
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  discovery_code VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (merchant_id, discovery_code)
);

INSERT INTO merchant_discovery_subcategory (merchant_id, discovery_code)
SELECT m.id, LOWER(TRIM(m.discovery_subcategory))
FROM merchant m
WHERE m.discovery_subcategory IS NOT NULL
  AND TRIM(m.discovery_subcategory) <> ''
ON CONFLICT (merchant_id, discovery_code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_merchant_discovery_subcategory_code
ON merchant_discovery_subcategory(discovery_code, merchant_id);

CREATE INDEX IF NOT EXISTS idx_merchant_discovery_select_all
ON merchant(discovery_select_all);

COMMIT;
