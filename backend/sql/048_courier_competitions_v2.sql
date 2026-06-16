BEGIN;

ALTER TABLE courier_competition
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'courier_competition_status_check'
  ) THEN
    ALTER TABLE courier_competition
      ADD CONSTRAINT courier_competition_status_check
      CHECK (status IN ('draft', 'active', 'ended', 'cancelled'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_courier_competition_status_window
ON courier_competition(status, start_at, end_at DESC);

CREATE TABLE IF NOT EXISTS courier_competition_tier (
  id BIGSERIAL PRIMARY KEY,
  competition_id BIGINT NOT NULL REFERENCES courier_competition(id) ON DELETE CASCADE,
  title VARCHAR(80),
  sort_order INT NOT NULL,
  required_completed_orders INT NOT NULL,
  reward_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  reward_label VARCHAR(120),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (competition_id, sort_order),
  UNIQUE (competition_id, required_completed_orders)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'courier_competition_tier_sort_order_check'
  ) THEN
    ALTER TABLE courier_competition_tier
      ADD CONSTRAINT courier_competition_tier_sort_order_check
      CHECK (sort_order > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'courier_competition_tier_required_orders_check'
  ) THEN
    ALTER TABLE courier_competition_tier
      ADD CONSTRAINT courier_competition_tier_required_orders_check
      CHECK (required_completed_orders > 0);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_courier_competition_tier_competition
ON courier_competition_tier(competition_id, required_completed_orders DESC, sort_order ASC);

CREATE TABLE IF NOT EXISTS courier_competition_counted_order (
  id BIGSERIAL PRIMARY KEY,
  competition_id BIGINT NOT NULL REFERENCES courier_competition(id) ON DELETE CASCADE,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  counted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (competition_id, courier_user_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_courier_competition_counted_order_competition
ON courier_competition_counted_order(competition_id, counted_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_competition_counted_order_courier
ON courier_competition_counted_order(courier_user_id, counted_at DESC);

CREATE TABLE IF NOT EXISTS courier_competition_result (
  id BIGSERIAL PRIMARY KEY,
  competition_id BIGINT NOT NULL REFERENCES courier_competition(id) ON DELETE CASCADE,
  courier_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  final_completed_orders INT NOT NULL DEFAULT 0,
  final_rank_sort_order INT,
  final_rank_title VARCHAR(80),
  reward_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  won BOOLEAN NOT NULL DEFAULT FALSE,
  result_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (competition_id, courier_user_id)
);

CREATE INDEX IF NOT EXISTS idx_courier_competition_result_competition
ON courier_competition_result(competition_id, won DESC, final_rank_sort_order ASC, final_completed_orders DESC);

CREATE INDEX IF NOT EXISTS idx_courier_competition_result_courier
ON courier_competition_result(courier_user_id, created_at DESC);

ALTER TABLE courier_competition_progress
  ADD COLUMN IF NOT EXISTS current_rank_sort_order INT,
  ADD COLUMN IF NOT EXISTS current_rank_title VARCHAR(80),
  ADD COLUMN IF NOT EXISTS highest_rank_sort_order INT,
  ADD COLUMN IF NOT EXISTS highest_rank_title VARCHAR(80),
  ADD COLUMN IF NOT EXISTS last_counted_order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_courier_competition_progress_rank
ON courier_competition_progress(courier_user_id, current_rank_sort_order, updated_at DESC);

-- Backfill a default tier for legacy competitions that don't have explicit tiers yet.
INSERT INTO courier_competition_tier (
  competition_id,
  title,
  sort_order,
  required_completed_orders,
  reward_amount,
  reward_label
)
SELECT
  cc.id,
  'Legacy tier',
  1,
  GREATEST(1, ROUND(COALESCE(cc.target_value, 1))::int),
  COALESCE(cc.reward_amount, 0),
  NULL
FROM courier_competition cc
WHERE NOT EXISTS (
  SELECT 1
  FROM courier_competition_tier cct
  WHERE cct.competition_id = cc.id
);

COMMIT;

