-- 168_taxi_cancellation_lock_and_emergency.sql
-- المرحلة 1: قفل إلغاء رحلة التاكسي + مخرج الطوارئ.
-- Forward-only. كل الأعمدة الجديدة nullable / defaulted حتى لا تتأثر الرحلات القديمة.

BEGIN;

-- (1) بيانات وصفية للإلغاء على طلب الرحلة: من ألغى، السبب، والحالة السابقة.
ALTER TABLE taxi_ride_request
  ADD COLUMN IF NOT EXISTS cancelled_by_role      VARCHAR(24),
  ADD COLUMN IF NOT EXISTS cancelled_by_user_id   BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancel_reason_code     VARCHAR(64),
  ADD COLUMN IF NOT EXISTS cancel_reason_text     TEXT,
  ADD COLUMN IF NOT EXISTS cancel_previous_status VARCHAR(32),
  ADD COLUMN IF NOT EXISTS cancel_is_emergency    BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE taxi_ride_request
  DROP CONSTRAINT IF EXISTS chk_taxi_ride_request_cancelled_by_role;
ALTER TABLE taxi_ride_request
  ADD CONSTRAINT chk_taxi_ride_request_cancelled_by_role
  CHECK (
    cancelled_by_role IS NULL
    OR cancelled_by_role IN ('customer', 'captain', 'admin', 'system')
  );

-- backfill: الرحلات الملغاة تاريخياً كانت جميعها بمبادرة الزبون.
UPDATE taxi_ride_request
SET cancelled_by_role = 'customer'
WHERE status = 'cancelled'
  AND cancelled_by_role IS NULL;

-- (2) تذكرة السلامة العاجلة المرتبطة بالرحلة (لا تُغيّر حالة الرحلة تلقائياً).
CREATE TABLE IF NOT EXISTS taxi_ride_emergency (
  id                      BIGSERIAL PRIMARY KEY,
  ride_request_id         BIGINT NOT NULL REFERENCES taxi_ride_request(id) ON DELETE CASCADE,
  reported_by_user_id     BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reported_by_role        VARCHAR(24) NOT NULL,
  ride_status_at_report   VARCHAR(32) NOT NULL,
  category                VARCHAR(48) NOT NULL DEFAULT 'safety',
  message                 TEXT,
  status                  VARCHAR(24) NOT NULL DEFAULT 'open',
  resolution              VARCHAR(48),
  resolution_note         TEXT,
  resolved_by_user_id     BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  resolved_at             TIMESTAMPTZ,
  second_approver_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  second_approved_at      TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_taxi_ride_emergency_role
    CHECK (reported_by_role IN ('customer', 'captain', 'admin', 'system')),
  CONSTRAINT chk_taxi_ride_emergency_status
    CHECK (status IN ('open', 'acknowledged', 'resolved', 'cancelled_ride', 'dismissed'))
);

CREATE INDEX IF NOT EXISTS idx_taxi_ride_emergency_status
  ON taxi_ride_emergency (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_taxi_ride_emergency_ride
  ON taxi_ride_emergency (ride_request_id, created_at DESC);

COMMIT;
