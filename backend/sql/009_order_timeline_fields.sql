BEGIN;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

ALTER TABLE customer_order
ADD COLUMN IF NOT EXISTS preparing_started_at TIMESTAMPTZ;

UPDATE customer_order
SET approved_at = COALESCE(
      approved_at,
      preparing_started_at,
      prepared_at,
      picked_up_at,
      delivered_at,
      customer_confirmed_at,
      created_at
    )
WHERE status <> 'pending'
  AND approved_at IS NULL;

UPDATE customer_order
SET preparing_started_at = COALESCE(
      preparing_started_at,
      approved_at,
      prepared_at
    )
WHERE status IN ('preparing','ready_for_delivery','on_the_way','delivered')
  AND preparing_started_at IS NULL;

COMMIT;
