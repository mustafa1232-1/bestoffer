-- Multi-store grouped delivery (delivery closure §3–§10).
--
-- Root cause fixed here: assignment was per child `customer_order`
-- (courier_assignment.order_id + customer_order.delivery_user_id) with no
-- grouped delivery entity, so a multi-store `order_group` produced inconsistent
-- per-child assignments — the UI could show "assigned" while the courier's
-- per-`delivery_user_id` query returned no coherent grouped job.
--
-- This adds the authoritative grouped model (one job per order_group, N pickup
-- stops) plus a transactional notification_outbox. Idempotent + non-destructive:
-- existing single-store per-order flow is untouched; grouped rows are created on
-- demand by the service layer.

BEGIN;

-- One grouped delivery job per customer checkout group.
CREATE TABLE IF NOT EXISTS delivery_job (
  id                     BIGSERIAL PRIMARY KEY,
  order_group_id         BIGINT NOT NULL REFERENCES order_group(id) ON DELETE CASCADE,
  customer_user_id       BIGINT NOT NULL REFERENCES app_user(id),
  delivery_user_id       BIGINT REFERENCES app_user(id),
  assignment_status      VARCHAR(32) NOT NULL DEFAULT 'PENDING_STORES',
  lifecycle_status       VARCHAR(32) NOT NULL DEFAULT 'PENDING_STORES',
  dropoff_address_snapshot_json JSONB,
  dropoff_latitude       DOUBLE PRECISION,
  dropoff_longitude      DOUBLE PRECISION,
  payment_method         VARCHAR(24),
  delivery_fee           NUMERIC(12,2) NOT NULL DEFAULT 0,
  courier_earning        NUMERIC(12,2) NOT NULL DEFAULT 0,
  assignment_attempt_count INT NOT NULL DEFAULT 0,
  idempotency_key        TEXT,
  version                INT NOT NULL DEFAULT 0,
  assigned_at            TIMESTAMPTZ,
  accepted_at            TIMESTAMPTZ,
  completed_at           TIMESTAMPTZ,
  cancelled_at           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Exactly one grouped job per order group (prevents duplicate active jobs /
-- concurrent-worker double assignment at the group level).
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_job_order_group
  ON delivery_job (order_group_id);

-- Idempotency for assignment attempts.
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_job_idempotency
  ON delivery_job (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delivery_job_assignment_status_check') THEN
    ALTER TABLE delivery_job ADD CONSTRAINT delivery_job_assignment_status_check
      CHECK (assignment_status IN (
        'PENDING_STORES','READY_FOR_ASSIGNMENT','PENDING_NO_DRIVER','ASSIGNED',
        'REASSIGNING','CANCELLED','FAILED'));
  END IF;
  -- A job may only be ASSIGNED with a courier, and must have a courier when assigned.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delivery_job_assigned_courier_check') THEN
    ALTER TABLE delivery_job ADD CONSTRAINT delivery_job_assigned_courier_check
      CHECK (
        (assignment_status = 'ASSIGNED' AND delivery_user_id IS NOT NULL)
        OR (assignment_status <> 'ASSIGNED')
      );
  END IF;
END $$;

-- One pickup stop per child order; a child order belongs to exactly one job.
CREATE TABLE IF NOT EXISTS delivery_pickup_stop (
  id                 BIGSERIAL PRIMARY KEY,
  delivery_job_id    BIGINT NOT NULL REFERENCES delivery_job(id) ON DELETE CASCADE,
  child_order_id     BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
  store_id           BIGINT NOT NULL,
  sequence_number    INT NOT NULL DEFAULT 1,
  pickup_status      VARCHAR(32) NOT NULL DEFAULT 'WAITING_STORE_ACCEPTANCE',
  preparation_status VARCHAR(32) NOT NULL DEFAULT 'PREPARING',
  address_snapshot_json JSONB,
  latitude           DOUBLE PRECISION,
  longitude          DOUBLE PRECISION,
  phone_snapshot     VARCHAR(32),
  ready_at           TIMESTAMPTZ,
  arrived_at         TIMESTAMPTZ,
  collected_at       TIMESTAMPTZ,
  cancelled_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_pickup_stop_child_order
  ON delivery_pickup_stop (child_order_id);

CREATE INDEX IF NOT EXISTS idx_delivery_pickup_stop_job
  ON delivery_pickup_stop (delivery_job_id, sequence_number);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delivery_pickup_stop_status_check') THEN
    ALTER TABLE delivery_pickup_stop ADD CONSTRAINT delivery_pickup_stop_status_check
      CHECK (pickup_status IN (
        'WAITING_STORE_ACCEPTANCE','PREPARING','READY','COURIER_ARRIVED','COLLECTED','CANCELLED'));
  END IF;
END $$;

-- Fast courier grouped-job lookup.
CREATE INDEX IF NOT EXISTS idx_delivery_job_courier_active
  ON delivery_job (delivery_user_id, assignment_status)
  WHERE delivery_user_id IS NOT NULL;

-- ROOT-CAUSE FIX. The legacy partial unique index
--   uq_customer_order_assigned_driver_active
--     = UNIQUE (delivery_user_id) WHERE delivery_assignment_status='ASSIGNED'
-- allowed a driver only ONE active assigned child order, which made assigning
-- one courier to the N child orders of a multi-store group impossible (the 2nd
-- child violated it). We scope it to SINGLE (non-group) orders only, and move
-- the authoritative "one active delivery per driver" invariant to delivery_job.
DROP INDEX IF EXISTS uq_customer_order_assigned_driver_active;
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_order_assigned_driver_active
  ON customer_order (delivery_user_id)
  WHERE delivery_assignment_status = 'ASSIGNED'
    AND delivery_user_id IS NOT NULL
    AND order_group_id IS NULL;

-- Authoritative: a courier may hold at most one active grouped job at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_job_assigned_courier_active
  ON delivery_job (delivery_user_id)
  WHERE assignment_status = 'ASSIGNED' AND delivery_user_id IS NOT NULL;

-- Transactional notification outbox (§9/§10). Business event + outbox row commit
-- together; a worker sends after commit. No such table existed before.
CREATE TABLE IF NOT EXISTS notification_outbox (
  id                    BIGSERIAL PRIMARY KEY,
  event_id              TEXT NOT NULL,
  event_type            VARCHAR(64) NOT NULL,
  recipient_user_id     BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  target_surface        VARCHAR(24) NOT NULL,
  target_entity_type    VARCHAR(48),
  target_entity_id      BIGINT,
  payload_json          JSONB NOT NULL DEFAULT '{}'::jsonb,
  priority              VARCHAR(16) NOT NULL DEFAULT 'high',
  status                VARCHAR(24) NOT NULL DEFAULT 'CREATED',
  attempt_count         INT NOT NULL DEFAULT 0,
  next_attempt_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  provider_message_id   TEXT,
  last_error_code       VARCHAR(64),
  last_error_message_safe TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at               TIMESTAMPTZ
);

-- Idempotent per event: one business event → one outbox row.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_outbox_event
  ON notification_outbox (event_id);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
  ON notification_outbox (status, next_attempt_at)
  WHERE status IN ('CREATED','QUEUED','PROVIDER_REJECTED');

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notification_outbox_status_check') THEN
    ALTER TABLE notification_outbox ADD CONSTRAINT notification_outbox_status_check
      CHECK (status IN ('CREATED','QUEUED','PROVIDER_ACCEPTED','PROVIDER_REJECTED','DEAD_LETTER'));
  END IF;
END $$;

COMMIT;
