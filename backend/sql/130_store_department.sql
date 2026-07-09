BEGIN;

-- ============================================================
-- 130  Store department / gender section for Fashion Market
-- ------------------------------------------------------------
-- Fashion & clothing stores (activity_type = 'fashion_clothing') must be
-- classified into a customer-facing department (رجالي / نسائي) so the Fashion
-- Market can show نسائي / رجالي first, then the stores of that section.
--
-- Forward-only, additive, idempotent. Non-fashion stores keep store_department
-- NULL (department is only required for fashion). Legacy fashion stores are
-- backfilled conservatively from their discovery subcategory or name/desc; any
-- store we cannot classify with confidence is marked 'needs_review' so it is
-- surfaced to admins and never silently lost or hidden.
-- ============================================================

ALTER TABLE merchant
  ADD COLUMN IF NOT EXISTS store_department VARCHAR(20);

-- Allowed values (NULL allowed for non-fashion stores).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'merchant_store_department_check'
  ) THEN
    ALTER TABLE merchant
      ADD CONSTRAINT merchant_store_department_check
      CHECK (
        store_department IS NULL
        OR store_department IN ('men', 'women', 'unisex', 'needs_review')
      );
  END IF;
END
$$;

-- 1) Backfill from explicit discovery subcategory selections (most reliable).
--    merchant_discovery_subcategory holds codes like 'women_fashion'/'men_fashion'.
WITH signals AS (
  SELECT
    m.id AS merchant_id,
    bool_or(
      mds.discovery_code IN ('women_fashion', 'womens', 'women', 'ladies')
    ) AS has_women,
    bool_or(
      mds.discovery_code IN ('men_fashion', 'mens', 'men', 'gents')
    ) AS has_men
  FROM merchant m
  JOIN merchant_discovery_subcategory mds ON mds.merchant_id = m.id
  WHERE m.activity_type = 'fashion_clothing'
  GROUP BY m.id
)
UPDATE merchant m
SET store_department = CASE
      WHEN s.has_women AND NOT s.has_men THEN 'women'
      WHEN s.has_men AND NOT s.has_women THEN 'men'
      WHEN s.has_men AND s.has_women THEN 'unisex'
      ELSE m.store_department
    END
FROM signals s
WHERE m.id = s.merchant_id
  AND m.store_department IS NULL
  AND (s.has_women OR s.has_men);

-- 2) Backfill from the legacy single discovery_subcategory column.
UPDATE merchant
SET store_department = CASE
      WHEN LOWER(discovery_subcategory) IN ('women_fashion', 'womens', 'women', 'ladies') THEN 'women'
      WHEN LOWER(discovery_subcategory) IN ('men_fashion', 'mens', 'men', 'gents') THEN 'men'
      ELSE store_department
    END
WHERE activity_type = 'fashion_clothing'
  AND store_department IS NULL
  AND discovery_subcategory IS NOT NULL;

-- 3) Conservative inference from name/description keywords (AR + EN).
--    Only classify when exactly one gender signal is present.
WITH text_signals AS (
  SELECT
    id,
    (
      LOWER(COALESCE(name, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(tagline, ''))
        ~ '(نساء|نسائي|نسائية|بناتي|women|woman|ladies|female|lingerie|عبايات|فساتين)'
    ) AS women_text,
    (
      LOWER(COALESCE(name, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(tagline, ''))
        ~ '(رجال|رجالي|رجالية|men|man|gents|male|بدلات)'
    ) AS men_text
  FROM merchant
  WHERE activity_type = 'fashion_clothing'
    AND store_department IS NULL
)
UPDATE merchant m
SET store_department = CASE
      WHEN t.women_text AND NOT t.men_text THEN 'women'
      WHEN t.men_text AND NOT t.women_text THEN 'men'
      ELSE m.store_department
    END
FROM text_signals t
WHERE m.id = t.id
  AND m.store_department IS NULL
  AND (t.women_text OR t.men_text)
  AND NOT (t.women_text AND t.men_text);

-- 4) Anything still unclassified but is a fashion store -> needs_review, so the
--    store stays visible to admins (never hidden) and is flagged for manual
--    classification. It will NOT appear in the customer نسائي/رجالي sections.
UPDATE merchant
SET store_department = 'needs_review'
WHERE activity_type = 'fashion_clothing'
  AND store_department IS NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_activity_department
  ON merchant (activity_type, store_department);

-- Admin review report: fashion stores still needing manual classification.
DO $$
DECLARE
  review_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO review_count
  FROM merchant
  WHERE activity_type = 'fashion_clothing' AND store_department = 'needs_review';
  RAISE NOTICE '[130] fashion stores needing manual department review: %', review_count;
END
$$;

COMMIT;
