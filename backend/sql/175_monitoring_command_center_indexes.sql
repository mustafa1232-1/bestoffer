-- 175_monitoring_command_center_indexes.sql
-- Query support for the unified monitoring command center.
-- No seed data, users, or demo records are created here.

BEGIN;

CREATE INDEX IF NOT EXISTS idx_customer_order_monitoring_status_updated
  ON customer_order (status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_monitoring_created
  ON customer_order (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_monitoring_delivery_user
  ON customer_order (delivery_user_id, status, updated_at DESC)
  WHERE delivery_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customer_order_monitoring_assignment
  ON customer_order (delivery_assignment_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_job_monitoring_status
  ON delivery_job (assignment_status, lifecycle_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_job_monitoring_courier
  ON delivery_job (delivery_user_id, assignment_status, updated_at DESC)
  WHERE delivery_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_courier_profile_monitoring
  ON courier_profile (availability_status, coverage_block, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_assignment_monitoring_active
  ON courier_assignment (courier_user_id, status, requested_at DESC)
  WHERE ended_at IS NULL;

COMMIT;
