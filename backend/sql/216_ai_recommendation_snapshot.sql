CREATE TABLE IF NOT EXISTS ai_recommendation_snapshot (
  id BIGSERIAL PRIMARY KEY,
  customer_user_id BIGINT NOT NULL,
  recommendation_type VARCHAR(32) NOT NULL,
  query_text TEXT,
  items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  model_name VARCHAR(120),
  confidence DOUBLE PRECISION NOT NULL DEFAULT 0.6,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_snapshot_customer_created
  ON ai_recommendation_snapshot (customer_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_recommendation_snapshot_type_created
  ON ai_recommendation_snapshot (recommendation_type, created_at DESC);
