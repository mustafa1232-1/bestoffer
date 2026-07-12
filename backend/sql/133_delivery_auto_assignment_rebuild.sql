BEGIN;

ALTER TABLE customer_order
  ADD COLUMN IF NOT EXISTS delivery_assignment_status TEXT NOT NULL DEFAULT 'NOT_REQUIRED';

ALTER TABLE courier_assignment
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;

ALTER TABLE courier_assignment
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

ALTER TABLE courier_assignment
  ADD COLUMN IF NOT EXISTS ended_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_customer_order_delivery_assignment_status'
  ) THEN
    ALTER TABLE customer_order
    ADD CONSTRAINT chk_customer_order_delivery_assignment_status
    CHECK (delivery_assignment_status IN (
      'NOT_REQUIRED',
      'PENDING_NO_DRIVER',
      'ASSIGNED',
      'COMPLETED',
      'CANCELLED'
    ));
  END IF;
END
$$;

UPDATE customer_order
SET delivery_assignment_status = CASE
  WHEN status::text IN ('cancelled', 'cancelled_by_customer', 'cancelled_by_store', 'cancelled_by_admin') THEN 'CANCELLED'
  WHEN status::text IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed') THEN 'COMPLETED'
  WHEN delivery_user_id IS NOT NULL AND status::text IN ('approved', 'preparing', 'ready_for_delivery', 'on_the_way', 'arrived') THEN 'ASSIGNED'
  WHEN status::text IN ('ready_for_delivery', 'ready_for_pickup') THEN 'PENDING_NO_DRIVER'
  ELSE 'NOT_REQUIRED'
END
WHERE delivery_assignment_status IS NULL
   OR delivery_assignment_status NOT IN (
     'NOT_REQUIRED',
     'PENDING_NO_DRIVER',
     'ASSIGNED',
     'COMPLETED',
     'CANCELLED'
   );

UPDATE courier_assignment
SET assigned_at = COALESCE(assigned_at, responded_at, requested_at, created_at, NOW()),
    ended_at = COALESCE(
      ended_at,
      CASE
        WHEN status IN ('assigned', 'accepted') THEN NULL
        WHEN status IN ('completed', 'released', 'cancelled', 'expired', 'rejected') THEN COALESCE(responded_at, requested_at, created_at, NOW())
        ELSE COALESCE(responded_at, requested_at, created_at, NOW())
      END
    ),
    ended_reason = COALESCE(
      ended_reason,
      CASE
        WHEN status = 'completed' THEN 'COMPLETED'
        WHEN status = 'released' THEN 'RELEASED'
        WHEN status = 'expired' THEN 'EXPIRED'
        WHEN status = 'cancelled' THEN 'ORDER_CANCELLED'
        WHEN status = 'rejected' THEN 'DRIVER_REJECTED'
        WHEN status = 'accepted' THEN NULL
        WHEN status = 'assigned' THEN NULL
        ELSE 'RELEASED'
      END
    ),
    status = CASE
      WHEN status IN ('accepted', 'assigned') AND ended_at IS NULL THEN 'assigned'
      WHEN status = 'completed' THEN 'completed'
      WHEN status = 'released' THEN 'released'
      WHEN status = 'expired' THEN 'expired'
      WHEN status = 'cancelled' THEN 'cancelled'
      WHEN status = 'rejected' THEN 'released'
      ELSE status
    END;

UPDATE courier_assignment ca
SET ended_at = NOW(),
    ended_reason = COALESCE(ended_reason, 'MIGRATED_DUPLICATE'),
    status = CASE
      WHEN ended_reason = 'COMPLETED' THEN 'completed'
      WHEN ended_reason = 'EXPIRED' THEN 'expired'
      WHEN ended_reason = 'ORDER_CANCELLED' THEN 'cancelled'
      ELSE 'released'
    END
FROM (
  SELECT order_id, MAX(id) AS keep_id
  FROM courier_assignment
  WHERE ended_at IS NULL
  GROUP BY order_id
) keep
WHERE ca.order_id = keep.order_id
  AND ca.ended_at IS NULL
  AND ca.id <> keep.keep_id;

UPDATE courier_assignment ca
SET ended_at = NOW(),
    ended_reason = COALESCE(ended_reason, 'MIGRATED_DUPLICATE'),
    status = 'released'
WHERE ca.ended_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM customer_order o
    WHERE o.id = ca.order_id
      AND o.delivery_user_id = ca.courier_user_id
      AND o.delivery_assignment_status = 'ASSIGNED'
  );

WITH ranked_active_orders AS (
  SELECT
    o.id,
    o.delivery_user_id,
    ROW_NUMBER() OVER (
      PARTITION BY o.delivery_user_id
      ORDER BY
        CASE o.status::text
          WHEN 'on_the_way' THEN 5
          WHEN 'arrived' THEN 4
          WHEN 'ready_for_delivery' THEN 3
          WHEN 'preparing' THEN 2
          WHEN 'approved' THEN 1
          ELSE 0
        END DESC,
        COALESCE(o.courier_assigned_at, o.updated_at, o.created_at) DESC,
        o.id DESC
    ) AS rn
  FROM customer_order o
  WHERE o.delivery_user_id IS NOT NULL
    AND o.delivery_assignment_status = 'ASSIGNED'
)
UPDATE customer_order o
SET delivery_user_id = NULL,
    delivery_assignment_status = CASE
      WHEN o.status::text IN ('cancelled', 'cancelled_by_customer', 'cancelled_by_store', 'cancelled_by_admin') THEN 'CANCELLED'
      WHEN o.status::text IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed') THEN 'COMPLETED'
      WHEN o.status::text IN ('approved', 'preparing', 'ready_for_delivery', 'ready_for_pickup', 'on_the_way', 'arrived') THEN 'PENDING_NO_DRIVER'
      ELSE 'NOT_REQUIRED'
    END,
    updated_at = NOW()
FROM ranked_active_orders r
WHERE o.id = r.id
  AND r.rn > 1;

INSERT INTO courier_assignment (
  order_id,
  courier_user_id,
  assignment_type,
  status,
  requested_by_user_id,
  requested_at,
  assigned_at,
  responded_at,
  expires_at,
  response_note,
  ended_at,
  ended_reason
)
SELECT
  o.id,
  o.delivery_user_id,
  'direct_assignment',
  'assigned',
  NULL,
  COALESCE(o.courier_assigned_at, o.updated_at, NOW()),
  COALESCE(o.courier_assigned_at, o.updated_at, NOW()),
  COALESCE(o.courier_assigned_at, o.updated_at, NOW()),
  NULL,
  NULL,
  NULL,
  NULL
FROM customer_order o
WHERE o.delivery_user_id IS NOT NULL
  AND o.delivery_assignment_status = 'ASSIGNED'
  AND NOT EXISTS (
    SELECT 1
    FROM courier_assignment ca
    WHERE ca.order_id = o.id
      AND ca.courier_user_id = o.delivery_user_id
      AND ca.ended_at IS NULL
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'uq_courier_assignment_open_order'
  ) THEN
    CREATE UNIQUE INDEX uq_courier_assignment_open_order
      ON courier_assignment(order_id)
      WHERE ended_at IS NULL;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'uq_courier_assignment_open_courier'
  ) THEN
    CREATE UNIQUE INDEX uq_courier_assignment_open_courier
      ON courier_assignment(courier_user_id)
      WHERE ended_at IS NULL;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'uq_customer_order_assigned_driver_active'
  ) THEN
    CREATE UNIQUE INDEX uq_customer_order_assigned_driver_active
      ON customer_order(delivery_user_id)
      WHERE delivery_assignment_status = 'ASSIGNED'
        AND delivery_user_id IS NOT NULL;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_customer_order_delivery_assignment_status
  ON customer_order (delivery_assignment_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_assignment_open_lookup
  ON courier_assignment (order_id, courier_user_id, ended_at DESC, requested_at DESC);

COMMIT;
