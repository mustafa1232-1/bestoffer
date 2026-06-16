-- ============================================================
-- 024  Product reviews (customer ratings for purchased products)
-- ============================================================

CREATE TABLE IF NOT EXISTS product_review (
  id              SERIAL PRIMARY KEY,
  product_id      INT         NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  customer_id     INT         NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  order_id        INT         REFERENCES customer_order(id) ON DELETE SET NULL,
  rating          SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body            TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One review per customer per product
  UNIQUE (product_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_product_review_product ON product_review(product_id);
CREATE INDEX IF NOT EXISTS idx_product_review_customer ON product_review(customer_id);

-- Aggregate view: average rating + review count per product
CREATE OR REPLACE VIEW product_rating_summary AS
SELECT
  product_id,
  ROUND(AVG(rating)::numeric, 2)  AS avg_rating,
  COUNT(*)                         AS review_count
FROM product_review
GROUP BY product_id;
