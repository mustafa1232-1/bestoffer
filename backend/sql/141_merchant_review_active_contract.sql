BEGIN;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_state VARCHAR(24) NOT NULL DEFAULT 'active';

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_deleted_at TIMESTAMPTZ;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_deleted_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_moderated_at TIMESTAMPTZ;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_moderated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS review_moderation_note TEXT;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS verified_purchase BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS verified_purchase_order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL;

ALTER TABLE social_post
  ADD COLUMN IF NOT EXISTS verified_purchase_verified_at TIMESTAMPTZ;

UPDATE merchant_verified_review
SET review_state = COALESCE(NULLIF(TRIM(review_state), ''), 'active')
WHERE review_state IS NULL
   OR TRIM(review_state) = '';

WITH ranked_reviews AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY merchant_id, customer_user_id
      ORDER BY
        COALESCE(updated_at, created_at, NOW()) DESC,
        id DESC
    ) AS rn
  FROM merchant_verified_review
  WHERE review_state IN ('active', 'restored')
)
UPDATE merchant_verified_review r
SET review_state = 'deleted',
    review_deleted_at = COALESCE(review_deleted_at, NOW()),
    review_moderated_at = COALESCE(review_moderated_at, NOW()),
    review_moderation_note = COALESCE(
      NULLIF(review_moderation_note, ''),
      'Superseded by migration 141 duplicate reconciliation'
    )
FROM ranked_reviews ranked
WHERE ranked.rn > 1
  AND ranked.id = r.id;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'merchant_verified_review_review_state_check'
  ) THEN
    ALTER TABLE merchant_verified_review
      ADD CONSTRAINT merchant_verified_review_review_state_check
      CHECK (review_state IN ('active', 'deleted', 'hidden', 'rejected', 'restored', 'pending_review'));
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_merchant_verified_review_customer_merchant_unique
  ON merchant_verified_review (merchant_id, customer_user_id)
  WHERE review_state IN ('active', 'restored');

CREATE INDEX IF NOT EXISTS idx_merchant_verified_review_merchant_state_recent
  ON merchant_verified_review (merchant_id, review_state, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_verified_review_customer_state_recent
  ON merchant_verified_review (customer_user_id, review_state, created_at DESC, id DESC);

COMMIT;
