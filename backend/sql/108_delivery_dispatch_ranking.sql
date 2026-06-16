BEGIN;

CREATE TABLE IF NOT EXISTS delivery_dispatch_policy (
  id BIGSERIAL PRIMARY KEY,
  policy_key VARCHAR(48) NOT NULL UNIQUE,
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO delivery_dispatch_policy (policy_key, config_json, is_active)
VALUES (
  'default',
  jsonb_build_object(
    'maxRecipients', 12,
    'waveSize', 4,
    'weights', jsonb_build_object(
      'rating', 0.42,
      'speed', 0.28,
      'proximity', 0.20,
      'availability', 0.10,
      'fatigue', 0.08
    ),
    'fallback', jsonb_build_object(
      'unratedCourierRating', 3.5,
      'avgDeliveryMinutes', 40,
      'sameBlockProximity', 1.0,
      'nearbyBlockProximity', 0.55
    )
  ),
  TRUE
)
ON CONFLICT (policy_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS delivery_dispatch_audit (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  requested_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  assignment_type VARCHAR(30) NOT NULL DEFAULT 'broadcast',
  customer_block VARCHAR(20),
  total_candidates INTEGER NOT NULL DEFAULT 0,
  wave_size INTEGER NOT NULL DEFAULT 1,
  couriers_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_dispatch_audit_order
ON delivery_dispatch_audit (order_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_dispatch_audit_merchant
ON delivery_dispatch_audit (merchant_id, created_at DESC);

ALTER TABLE courier_assignment
  ADD COLUMN IF NOT EXISTS dispatch_rank INTEGER,
  ADD COLUMN IF NOT EXISTS dispatch_wave INTEGER;

CREATE INDEX IF NOT EXISTS idx_courier_assignment_wave
ON courier_assignment (order_id, status, dispatch_wave, dispatch_rank, requested_at DESC);

COMMIT;
