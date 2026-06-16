BEGIN;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS merchant_rating SMALLINT;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS merchant_review TEXT;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS merchant_rated_at TIMESTAMPTZ;

ALTER TABLE customer_order
DROP CONSTRAINT IF EXISTS customer_order_merchant_rating_check;

ALTER TABLE customer_order
ADD CONSTRAINT customer_order_merchant_rating_check
CHECK (merchant_rating IS NULL OR merchant_rating BETWEEN 1 AND 5);

CREATE TABLE IF NOT EXISTS merchant_verified_review (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text TEXT,
  is_verified BOOLEAN NOT NULL DEFAULT TRUE,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (order_id),
  UNIQUE (merchant_id, customer_user_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_verified_review_merchant
ON merchant_verified_review (merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_verified_review_customer
ON merchant_verified_review (customer_user_id, created_at DESC);

CREATE OR REPLACE FUNCTION set_merchant_verified_review_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_merchant_verified_review_updated ON merchant_verified_review;
CREATE TRIGGER trg_merchant_verified_review_updated
BEFORE UPDATE ON merchant_verified_review
FOR EACH ROW
EXECUTE FUNCTION set_merchant_verified_review_updated_at();

INSERT INTO merchant_verified_review
  (order_id, merchant_id, customer_user_id, rating, review_text, is_verified, metadata_json)
SELECT
  o.id,
  o.merchant_id,
  o.customer_user_id,
  o.merchant_rating,
  o.merchant_review,
  TRUE,
  jsonb_build_object(
    'source', 'customer_order_backfill',
    'merchantRatedAt', o.merchant_rated_at
  )
FROM customer_order o
WHERE o.merchant_rating IS NOT NULL
  AND o.status IN ('delivered', 'completed')
ON CONFLICT (order_id) DO UPDATE
SET rating = EXCLUDED.rating,
    review_text = EXCLUDED.review_text,
    updated_at = NOW(),
    metadata_json = merchant_verified_review.metadata_json || EXCLUDED.metadata_json;

COMMIT;
