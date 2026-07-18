BEGIN;

-- Backfill grouped jobs that already reached terminal delivery so they no
-- longer occupy the active-courier unique index.
UPDATE delivery_job
   SET assignment_status = 'COMPLETED',
       updated_at = NOW()
 WHERE lifecycle_status = 'DELIVERED'
   AND assignment_status = 'ASSIGNED';

-- Allow the terminal grouped assignment state without treating the courier as
-- active. The live courier uniqueness still applies only to ASSIGNED rows.
ALTER TABLE delivery_job DROP CONSTRAINT IF EXISTS delivery_job_assignment_status_check;
ALTER TABLE delivery_job ADD CONSTRAINT delivery_job_assignment_status_check
  CHECK (assignment_status IN (
    'PENDING_STORES',
    'READY_FOR_ASSIGNMENT',
    'PENDING_NO_DRIVER',
    'ASSIGNED',
    'COMPLETED',
    'REASSIGNING',
    'CANCELLED',
    'FAILED'
  ));

COMMIT;
