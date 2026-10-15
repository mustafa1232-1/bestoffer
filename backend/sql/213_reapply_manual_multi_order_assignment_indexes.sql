BEGIN;

DROP INDEX IF EXISTS uq_courier_assignment_open_courier;
DROP INDEX IF EXISTS uq_customer_order_assigned_driver_active;

CREATE INDEX IF NOT EXISTS idx_courier_assignment_open_courier_lookup
  ON courier_assignment (courier_user_id, requested_at DESC, id DESC)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_customer_order_assigned_driver_active_lookup
  ON customer_order (delivery_user_id, updated_at DESC, id DESC)
  WHERE delivery_assignment_status = 'ASSIGNED'
    AND delivery_user_id IS NOT NULL;

COMMIT;
