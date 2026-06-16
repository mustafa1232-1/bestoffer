BEGIN;

CREATE TABLE IF NOT EXISTS customer_reliability_policy (
  id BIGSERIAL PRIMARY KEY,
  policy_key VARCHAR(48) NOT NULL UNIQUE,
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customer_reliability_snapshot (
  customer_user_id BIGINT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  score NUMERIC(6,2) NOT NULL DEFAULT 70,
  reliability_tier VARCHAR(24) NOT NULL DEFAULT 'medium',
  completed_orders_count INTEGER NOT NULL DEFAULT 0,
  cancelled_by_customer_count INTEGER NOT NULL DEFAULT 0,
  failed_delivery_count INTEGER NOT NULL DEFAULT 0,
  no_answer_count INTEGER NOT NULL DEFAULT 0,
  complaints_count INTEGER NOT NULL DEFAULT 0,
  last_successful_order_at TIMESTAMPTZ,
  warning_required BOOLEAN NOT NULL DEFAULT FALSE,
  snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_reliability_tier
ON customer_reliability_snapshot (reliability_tier, warning_required, score);

CREATE TABLE IF NOT EXISTS customer_reliability_override (
  id BIGSERIAL PRIMARY KEY,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  actor_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  override_type VARCHAR(24) NOT NULL,
  score_override NUMERIC(6,2),
  tier_override VARCHAR(24),
  note TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_reliability_override_customer
ON customer_reliability_override (customer_user_id, created_at DESC);

INSERT INTO customer_reliability_policy (policy_key, config_json, is_active)
VALUES (
  'default',
  jsonb_build_object(
    'windowDays', 180,
    'baseScore', 70,
    'weights', jsonb_build_object(
      'completed', 4,
      'cancelledByCustomer', -8,
      'failedDelivery', -10,
      'noAnswer', -9,
      'complaints', -12
    ),
    'thresholds', jsonb_build_object(
      'trustedMin', 80,
      'needsAttentionMax', 45
    ),
    'warningThreshold', 50
  ),
  TRUE
)
ON CONFLICT (policy_key) DO NOTHING;

COMMIT;
