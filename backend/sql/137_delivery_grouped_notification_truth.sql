-- Grouped delivery: truthful notification delivery + authoritative grouped
-- courier_assignment (delivery closure §1, §2, §5, §6).
--
-- Migration 136 is already applied to the local test DB and MUST NOT be edited;
-- this migration carries the corrections on top of it. Idempotent + additive.

BEGIN;

-- =========================================================================
-- §2  app_notification idempotency: one outbox event → at most one row.
-- =========================================================================
ALTER TABLE app_notification ADD COLUMN IF NOT EXISTS event_id TEXT;

-- Partial unique: only enforced for rows that carry an event_id, so the vast
-- majority of legacy/non-outbox notifications (event_id NULL) are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_notification_event_id
  ON app_notification (event_id)
  WHERE event_id IS NOT NULL;

-- =========================================================================
-- §1  notification_outbox: truthful delivery state machine + crash recovery.
-- =========================================================================
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS app_notification_id BIGINT
  REFERENCES app_notification(id) ON DELETE SET NULL;
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMPTZ;
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS provider_result_json JSONB;
ALTER TABLE notification_outbox ADD COLUMN IF NOT EXISTS schema_version INT NOT NULL DEFAULT 1;

-- §5 surface normalization: the authoritative courier surface is `delivery`
-- (resolveRoleAppSurface maps the delivery role → 'delivery'). Migration 136
-- wrote target_surface='courier'; normalize any such rows.
UPDATE notification_outbox SET target_surface='delivery' WHERE target_surface='courier';

-- Migrate legacy statuses to the truthful machine BEFORE swapping the CHECK:
--   CREATED            → CREATED   (unsent)
--   QUEUED             → CREATED   (was only "picked", never truly accepted)
--   PROVIDER_ACCEPTED  → PUSH_ACCEPTED (best-effort remap; new sends are precise)
--   PROVIDER_REJECTED  → PUSH_RETRY
--   DEAD_LETTER        → DEAD_LETTER
UPDATE notification_outbox SET status='CREATED'       WHERE status='QUEUED';
UPDATE notification_outbox SET status='PUSH_ACCEPTED'  WHERE status='PROVIDER_ACCEPTED';
UPDATE notification_outbox SET status='PUSH_RETRY'     WHERE status='PROVIDER_REJECTED';

-- Truthful state machine. app_notification creation is NOT provider acceptance;
-- push acceptance is recorded only from a real provider result.
ALTER TABLE notification_outbox DROP CONSTRAINT IF EXISTS notification_outbox_status_check;
ALTER TABLE notification_outbox ADD CONSTRAINT notification_outbox_status_check
  CHECK (status IN (
    'CREATED',              -- persisted, not yet processed
    'PROCESSING',           -- leased by a worker
    'NOTIFICATION_CREATED', -- app_notification row exists; push not yet resolved
    'PUSH_ACCEPTED',        -- provider accepted for all target tokens
    'PUSH_PARTIAL',         -- provider accepted some, others failed/dead
    'PUSH_RETRY',           -- retryable failure (incl. Firebase not configured)
    'PUSH_FAILED',          -- permanent failure / no eligible tokens
    'DEAD_LETTER'           -- attempts exhausted
  ));

-- Re-point the "due work" index at the truthful retryable states.
DROP INDEX IF EXISTS idx_notification_outbox_pending;
CREATE INDEX IF NOT EXISTS idx_notification_outbox_due
  ON notification_outbox (status, next_attempt_at)
  WHERE status IN ('CREATED','PROCESSING','NOTIFICATION_CREATED','PUSH_PARTIAL','PUSH_RETRY');

-- =========================================================================
-- §6  Authoritative grouped courier_assignment.
--   - existing single-order order_id path stays
--   - nullable delivery_job_id added; exactly one of the two is authoritative
--   - one active grouped assignment per delivery_job
-- =========================================================================
ALTER TABLE courier_assignment ALTER COLUMN order_id DROP NOT NULL;
ALTER TABLE courier_assignment ADD COLUMN IF NOT EXISTS delivery_job_id BIGINT
  REFERENCES delivery_job(id) ON DELETE CASCADE;
ALTER TABLE courier_assignment ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE courier_assignment ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE courier_assignment ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE courier_assignment ADD COLUMN IF NOT EXISTS correlation_id TEXT;

-- Exactly one authoritative target: a single order, or a grouped job.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='courier_assignment_target_check') THEN
    ALTER TABLE courier_assignment ADD CONSTRAINT courier_assignment_target_check
      CHECK (num_nonnulls(order_id, delivery_job_id) = 1);
  END IF;
END $$;

-- At most one active (not ended) grouped assignment per delivery_job.
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_assignment_active_job
  ON courier_assignment (delivery_job_id)
  WHERE delivery_job_id IS NOT NULL AND ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_courier_assignment_job
  ON courier_assignment (delivery_job_id, status);

-- Backfill: any delivery_job already ASSIGNED (e.g. created via migration 136 +
-- the grouped worker before this migration) gets its authoritative grouped
-- courier_assignment row. Completed/cancelled jobs are skipped.
INSERT INTO courier_assignment
  (delivery_job_id, courier_user_id, assignment_type, status, assigned_at, requested_at, correlation_id)
SELECT j.id, j.delivery_user_id, 'grouped', 'assigned', COALESCE(j.assigned_at, NOW()), COALESCE(j.assigned_at, NOW()),
       'backfill-137-job-' || j.id
  FROM delivery_job j
 WHERE j.assignment_status = 'ASSIGNED'
   AND j.delivery_user_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM courier_assignment ca
      WHERE ca.delivery_job_id = j.id AND ca.ended_at IS NULL
   );

COMMIT;
