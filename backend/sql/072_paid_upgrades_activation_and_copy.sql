BEGIN;

UPDATE paid_upgrade_plan
SET
  title = CASE code
    WHEN 'car_seller_monthly' THEN 'بائع سيارات شهري'
    WHEN 'property_seller_monthly' THEN 'دلال / مؤجر عقارات شهري'
    WHEN 'premium_monthly' THEN 'بريميوم شهري'
    ELSE title
  END,
  description = CASE code
    WHEN 'car_seller_monthly' THEN 'يمنحك نشر وإدارة إعلانات السيارات لمدة 30 يومًا داخل سوق السيارات، مع مساحة لإدارة سياراتك من حسابك.'
    WHEN 'property_seller_monthly' THEN 'يمنحك نشر وإدارة إعلانات الشقق والعقارات لمدة 30 يومًا داخل عقارات بسماية، مع مساحة لإدارة عقاراتك من حسابك.'
    WHEN 'premium_monthly' THEN 'يشمل شارة مستخدم موثق ظاهرة للجميع داخل السوشل، وميزات الحساب المميز، وصلاحية بائع السيارات، وصلاحية دلال أو مؤجر العقارات معًا لمدة 30 يومًا.'
    ELSE description
  END,
  badge_label = CASE code
    WHEN 'car_seller_monthly' THEN 'بائع سيارات'
    WHEN 'property_seller_monthly' THEN 'دلال عقارات'
    WHEN 'premium_monthly' THEN 'بريميوم'
    ELSE badge_label
  END,
  updated_at = NOW()
WHERE code IN (
  'car_seller_monthly',
  'property_seller_monthly',
  'premium_monthly'
);

CREATE TEMP TABLE tmp_paid_upgrade_backfill AS
SELECT DISTINCT ON (r.user_id, r.plan_id)
  r.id AS request_id,
  r.user_id,
  r.plan_id,
  COALESCE(r.reviewed_at, r.created_at, NOW()) AS started_at,
  COALESCE(r.reviewed_by_user_id, r.activated_by_user_id) AS actor_user_id
FROM paid_upgrade_request r
LEFT JOIN paid_upgrade_subscription linked_sub
  ON linked_sub.request_id = r.id
LEFT JOIN paid_upgrade_subscription active_sub
  ON active_sub.user_id = r.user_id
 AND active_sub.plan_id = r.plan_id
 AND active_sub.status = 'active'
 AND active_sub.expires_at > NOW()
WHERE r.status = 'approved'
  AND linked_sub.id IS NULL
  AND active_sub.id IS NULL
ORDER BY
  r.user_id,
  r.plan_id,
  COALESCE(r.reviewed_at, r.created_at, NOW()) DESC,
  r.id DESC;

CREATE TEMP TABLE tmp_paid_upgrade_backfill_inserted AS
WITH inserted_rows AS (
  INSERT INTO paid_upgrade_subscription (
    user_id,
    plan_id,
    request_id,
    status,
    started_at,
    expires_at,
    activated_by_user_id
  )
  SELECT
    user_id,
    plan_id,
    request_id,
    'active',
    started_at,
    started_at + INTERVAL '30 days',
    actor_user_id
  FROM tmp_paid_upgrade_backfill
  RETURNING id, request_id, user_id, plan_id, expires_at
)
SELECT * FROM inserted_rows;

UPDATE paid_upgrade_request r
SET
  status = 'activated',
  activated_by_user_id = COALESCE(r.reviewed_by_user_id, r.activated_by_user_id),
  activated_at = COALESCE(r.reviewed_at, NOW()),
  updated_at = NOW()
FROM tmp_paid_upgrade_backfill_inserted s
WHERE r.id = s.request_id;

INSERT INTO paid_upgrade_audit (
  request_id,
  subscription_id,
  actor_user_id,
  action_key,
  note,
  payload_json
)
SELECT
  s.request_id,
  s.id,
  COALESCE(r.reviewed_by_user_id, r.activated_by_user_id),
  'activated',
  'Backfilled approved request into active subscription',
  jsonb_build_object(
    'planId', s.plan_id,
    'userId', s.user_id,
    'expiresAt', s.expires_at
  )
FROM tmp_paid_upgrade_backfill_inserted s
JOIN paid_upgrade_request r ON r.id = s.request_id;

DROP TABLE IF EXISTS tmp_paid_upgrade_backfill_inserted;
DROP TABLE IF EXISTS tmp_paid_upgrade_backfill;

COMMIT;
