BEGIN;

ALTER TABLE merchant_delivery_agent
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE merchant_delivery_agent
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE merchant_delivery_agent
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE courier_profile
ADD COLUMN IF NOT EXISTS driver_type VARCHAR(20);

INSERT INTO courier_profile (
  user_id,
  is_app_courier,
  is_merchant_courier,
  merchant_id,
  active_status,
  availability_status,
  driver_type,
  created_at,
  updated_at
)
SELECT
  u.id,
  CASE WHEN linked.merchant_id IS NULL THEN TRUE ELSE FALSE END,
  CASE WHEN linked.merchant_id IS NULL THEN FALSE ELSE TRUE END,
  linked.merchant_id,
  TRUE,
  'online',
  CASE WHEN linked.merchant_id IS NULL THEN 'app_driver' ELSE 'store_driver' END,
  NOW(),
  NOW()
FROM app_user u
LEFT JOIN LATERAL (
  SELECT mda.merchant_id
  FROM merchant_delivery_agent mda
  WHERE mda.delivery_user_id = u.id
    AND mda.is_active = TRUE
  ORDER BY mda.updated_at DESC NULLS LAST, mda.merchant_id DESC
  LIMIT 1
) linked ON TRUE
WHERE u.role = 'delivery'
  AND NOT EXISTS (
    SELECT 1
    FROM courier_profile cp
    WHERE cp.user_id = u.id
  );

UPDATE courier_profile cp
SET driver_type = CASE
      WHEN EXISTS (
        SELECT 1
        FROM merchant_delivery_agent mda
        WHERE mda.delivery_user_id = cp.user_id
          AND mda.is_active = TRUE
      )
      THEN 'store_driver'
      ELSE 'app_driver'
    END,
    updated_at = NOW()
WHERE cp.driver_type IS NULL
   OR cp.driver_type NOT IN ('app_driver', 'store_driver');

UPDATE courier_profile cp
SET is_app_courier = (cp.driver_type = 'app_driver'),
    is_merchant_courier = (cp.driver_type = 'store_driver'),
    merchant_id = CASE
      WHEN cp.driver_type = 'store_driver' THEN COALESCE(
        (
          SELECT mda.merchant_id
          FROM merchant_delivery_agent mda
          WHERE mda.delivery_user_id = cp.user_id
            AND mda.is_active = TRUE
          ORDER BY mda.updated_at DESC NULLS LAST, mda.merchant_id DESC
          LIMIT 1
        ),
        cp.merchant_id
      )
      ELSE cp.merchant_id
    END,
    updated_at = NOW();

UPDATE app_user u
SET delivery_account_approved = TRUE,
    delivery_approved_at = COALESCE(delivery_approved_at, NOW())
WHERE u.role = 'delivery'
  AND EXISTS (
    SELECT 1
    FROM merchant_delivery_agent mda
    WHERE mda.delivery_user_id = u.id
      AND mda.is_active = TRUE
  )
  AND u.delivery_account_approved = FALSE;

UPDATE customer_order o
SET courier_source = CASE
      WHEN o.courier_source IS NOT NULL THEN o.courier_source
      WHEN COALESCE(o.is_merchant_delivery, FALSE) = TRUE THEN 'merchant'
      ELSE 'app'
    END
WHERE o.delivery_user_id IS NOT NULL
   OR COALESCE(o.is_merchant_delivery, FALSE) = TRUE;

ALTER TABLE courier_profile
ALTER COLUMN driver_type SET DEFAULT 'app_driver';

UPDATE courier_profile
SET driver_type = 'app_driver'
WHERE driver_type IS NULL;

ALTER TABLE courier_profile
ALTER COLUMN driver_type SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_courier_profile_driver_type'
  ) THEN
    ALTER TABLE courier_profile
    ADD CONSTRAINT chk_courier_profile_driver_type
    CHECK (driver_type IN ('app_driver', 'store_driver'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_courier_profile_driver_type
ON courier_profile(driver_type, active_status, availability_status);

COMMIT;
