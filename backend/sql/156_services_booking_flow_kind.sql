BEGIN;

ALTER TABLE service_requests
  ADD COLUMN IF NOT EXISTS booking_flow_kind VARCHAR(12);

ALTER TABLE service_requests
  ALTER COLUMN booking_flow_kind SET DEFAULT 'LEGACY';

DO $$
DECLARE
  v2_count BIGINT := 0;
  null_count BIGINT := 0;
  sample_v2_id BIGINT := NULL;
BEGIN
  SELECT COUNT(*) INTO v2_count
  FROM service_requests
  WHERE booking_flow_kind = 'V2';

  SELECT COUNT(*) INTO null_count
  FROM service_requests
  WHERE booking_flow_kind IS NULL;

  IF v2_count = 0 THEN
    UPDATE service_requests
    SET booking_flow_kind = 'LEGACY'
    WHERE booking_flow_kind IS NULL;
    RAISE NOTICE 'services.booking_flow_kind backfill: set % rows to LEGACY', null_count;
  ELSE
    SELECT id
    INTO sample_v2_id
    FROM service_requests
    WHERE booking_flow_kind = 'V2'
    ORDER BY id ASC
    LIMIT 1;
    RAISE NOTICE 'services.booking_flow_kind read-only: found % V2 rows, sample_id=%; skipped null backfill for % rows',
      v2_count,
      sample_v2_id,
      null_count;
  END IF;
END $$;

ALTER TABLE service_requests
  DROP CONSTRAINT IF EXISTS service_requests_booking_flow_kind_chk;

ALTER TABLE service_requests
  ADD CONSTRAINT service_requests_booking_flow_kind_chk
  CHECK (booking_flow_kind IN ('LEGACY', 'V2'));

CREATE OR REPLACE FUNCTION service_requests_booking_flow_kind_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.booking_flow_kind := COALESCE(NULLIF(BTRIM(NEW.booking_flow_kind), ''), 'LEGACY');
    IF NEW.booking_flow_kind NOT IN ('LEGACY', 'V2') THEN
      RAISE EXCEPTION 'invalid booking_flow_kind: %', NEW.booking_flow_kind
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.booking_flow_kind IS DISTINCT FROM OLD.booking_flow_kind THEN
    RAISE EXCEPTION 'booking_flow_kind is immutable'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_service_requests_booking_flow_kind_immutable ON service_requests;

CREATE TRIGGER trg_service_requests_booking_flow_kind_immutable
BEFORE INSERT OR UPDATE OF booking_flow_kind ON service_requests
FOR EACH ROW
EXECUTE FUNCTION service_requests_booking_flow_kind_immutable();

COMMIT;
