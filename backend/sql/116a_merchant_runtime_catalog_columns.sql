BEGIN;

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS activity_type VARCHAR(80),
  ADD COLUMN IF NOT EXISTS discovery_subcategory VARCHAR(120),
  ADD COLUMN IF NOT EXISTS discovery_select_all BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS tagline VARCHAR(160),
  ADD COLUMN IF NOT EXISTS working_hours VARCHAR(160),
  ADD COLUMN IF NOT EXISTS service_area_note VARCHAR(240),
  ADD COLUMN IF NOT EXISTS service_flags_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS supports_chat BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS supports_attachments BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS supports_pharmacy_workflow BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS badges_json JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE merchant
SET
  service_flags_json = COALESCE(service_flags_json, '{}'::jsonb),
  badges_json = COALESCE(badges_json, '[]'::jsonb),
  supports_chat = COALESCE(supports_chat, FALSE),
  supports_attachments = COALESCE(supports_attachments, FALSE),
  supports_pharmacy_workflow = COALESCE(supports_pharmacy_workflow, FALSE),
  discovery_select_all = COALESCE(discovery_select_all, FALSE)
WHERE
  service_flags_json IS NULL
  OR badges_json IS NULL
  OR supports_chat IS NULL
  OR supports_attachments IS NULL
  OR supports_pharmacy_workflow IS NULL
  OR discovery_select_all IS NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_activity_type_v2
ON merchant(activity_type);

CREATE INDEX IF NOT EXISTS idx_merchant_discovery_subcategory_v2
ON merchant(activity_type, discovery_subcategory);

CREATE INDEX IF NOT EXISTS idx_merchant_discovery_select_all_v2
ON merchant(discovery_select_all);

COMMIT;
