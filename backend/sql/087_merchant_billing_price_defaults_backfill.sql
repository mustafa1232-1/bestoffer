BEGIN;

-- Purpose:
-- إصلاح ملفات التسعير المعطوبة التي أصبحت كلها صفراً (عمولة/خدمة/توصيل)
-- بسبب إدخالات رقمية غير صالحة في بعض الواجهات.
--
-- Safety:
-- لا نلمس أي ملف تسعير فيه قيمة موجبة واحدة على الأقل؛
-- التعديل يطبق فقط على الحالات الشاذة "كلها صفر/فارغة".

UPDATE merchant_billing_profile
SET
  commission_type = COALESCE(NULLIF(TRIM(commission_type), ''), 'percentage'),
  commission_value = CASE
    WHEN COALESCE(commission_value, 0) <= 0 THEN 10
    ELSE commission_value
  END,
  commission_rate = CASE
    WHEN COALESCE(commission_rate, 0) <= 0 THEN 0.10
    ELSE commission_rate
  END,
  service_fee_type = COALESCE(NULLIF(TRIM(service_fee_type), ''), 'fixed'),
  service_fee_mode = CASE
    WHEN COALESCE(NULLIF(TRIM(service_fee_mode), ''), 'fixed') IN ('fixed', 'percentage')
      THEN COALESCE(NULLIF(TRIM(service_fee_mode), ''), 'fixed')
    ELSE 'fixed'
  END,
  service_fee_value = CASE
    WHEN COALESCE(service_fee_value, 0) <= 0 THEN 500
    ELSE service_fee_value
  END,
  delivery_fee_mode = CASE
    WHEN COALESCE(NULLIF(TRIM(delivery_fee_mode), ''), 'dynamic') IN ('app_defined', 'store_defined', 'dynamic', 'fixed', 'percentage')
      THEN COALESCE(NULLIF(TRIM(delivery_fee_mode), ''), 'dynamic')
    ELSE 'dynamic'
  END,
  app_delivery_fee_value = CASE
    WHEN COALESCE(app_delivery_fee_value, 0) <= 0 THEN COALESCE(NULLIF(delivery_fee_value, 0), 1000)
    ELSE app_delivery_fee_value
  END,
  store_delivery_fee_value = CASE
    WHEN store_delivery_fee_value IS NULL OR store_delivery_fee_value < 0 THEN 0
    ELSE store_delivery_fee_value
  END,
  app_delivery_enabled = COALESCE(app_delivery_enabled, TRUE),
  merchant_delivery_enabled = COALESCE(merchant_delivery_enabled, TRUE),
  updated_at = NOW()
WHERE
  COALESCE(commission_value, 0) <= 0
  AND COALESCE(commission_rate, 0) <= 0
  AND COALESCE(service_fee_value, 0) <= 0
  AND COALESCE(app_delivery_fee_value, 0) <= 0
  AND COALESCE(delivery_fee_value, 0) <= 0;

COMMIT;
