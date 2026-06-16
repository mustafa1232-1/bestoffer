CREATE TABLE IF NOT EXISTS merchant_delivery_agent (
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  delivery_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  source VARCHAR(20) NOT NULL DEFAULT 'owner',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (merchant_id, delivery_user_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_delivery_agent_delivery
  ON merchant_delivery_agent (delivery_user_id, is_active, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_delivery_agent_merchant
  ON merchant_delivery_agent (merchant_id, is_active, updated_at DESC);

UPDATE merchant_delivery_agent
SET updated_at = COALESCE(updated_at, NOW());

INSERT INTO merchant_delivery_agent (
  merchant_id,
  delivery_user_id,
  created_by_user_id,
  source,
  is_active
)
SELECT DISTINCT
  o.merchant_id,
  o.delivery_user_id,
  NULL::BIGINT,
  'system'::VARCHAR(20),
  TRUE
FROM customer_order o
JOIN app_user u
  ON u.id = o.delivery_user_id
WHERE o.delivery_user_id IS NOT NULL
  AND u.role = 'delivery'
  AND NOT EXISTS (
    SELECT 1
    FROM taxi_captain_profile tcp
    WHERE tcp.user_id = u.id
  )
ON CONFLICT (merchant_id, delivery_user_id)
DO UPDATE SET
  is_active = TRUE,
  updated_at = NOW();
