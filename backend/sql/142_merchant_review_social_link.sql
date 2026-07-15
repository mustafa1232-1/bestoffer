BEGIN;

ALTER TABLE merchant_verified_review
  ADD COLUMN IF NOT EXISTS social_post_id BIGINT REFERENCES social_post(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_merchant_verified_review_social_post_unique
  ON merchant_verified_review (social_post_id)
  WHERE social_post_id IS NOT NULL;

WITH exact_matches AS (
  SELECT
    r.id AS review_id,
    p.id AS post_id,
    ROW_NUMBER() OVER (
      PARTITION BY r.id
      ORDER BY p.created_at DESC, p.id DESC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY r.id) AS candidate_count
  FROM merchant_verified_review r
  JOIN social_post p
    ON p.post_kind = 'merchant_review'
   AND p.user_id = r.customer_user_id
   AND p.merchant_id = r.merchant_id
   AND p.review_rating = r.rating
   AND p.verified_purchase = TRUE
   AND p.verified_purchase_order_id = r.order_id
  WHERE r.social_post_id IS NULL
)
UPDATE merchant_verified_review r
SET social_post_id = exact_matches.post_id
FROM exact_matches
WHERE exact_matches.review_id = r.id
  AND exact_matches.rn = 1
  AND exact_matches.candidate_count = 1;

UPDATE merchant_verified_review r
SET review_moderation_note = COALESCE(
  NULLIF(review_moderation_note, ''),
  'Ambiguous merchant review social post reconciliation during migration 142'
)
WHERE r.social_post_id IS NULL
  AND EXISTS (
    SELECT 1
    FROM social_post p
    WHERE p.post_kind = 'merchant_review'
      AND p.user_id = r.customer_user_id
      AND p.merchant_id = r.merchant_id
      AND p.review_rating = r.rating
      AND p.verified_purchase = TRUE
      AND p.verified_purchase_order_id = r.order_id
    GROUP BY p.verified_purchase_order_id
    HAVING COUNT(*) > 1
  );

COMMIT;
