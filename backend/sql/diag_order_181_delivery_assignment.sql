-- ============================================================================
-- Delivery assignment diagnostics for a specific order (default: #181).
--
-- Purpose: prove FROM THE DATABASE (not by assumption) whether an assigned
-- order should be visible in the delivery app, and — if it is not being
-- assigned — WHY the eligible-driver pool is empty.
--
-- Canonical rule this script checks:
--   customer_order.delivery_user_id  MUST equal the authenticated delivery
--   account's app_user.id (the JWT `sub`), NOT a courier_profile id, taxi
--   captain profile id, device id, or store courier id.
--
-- Usage (psql):   \set order_id 181   then run this file.
-- If your client does not support \set, replace :order_id below with 181.
-- Read-only: only SELECTs, safe to run against production.
-- ============================================================================

\if :{?order_id}
\else
\set order_id 181
\endif

-- 1) The order itself: status + assignment fields.
SELECT
  o.id                          AS order_id,
  o.status,
  o.delivery_assignment_status,
  o.delivery_user_id,
  o.is_merchant_delivery,
  o.courier_source,
  o.assigned_by_store,
  o.courier_requested_at,
  o.courier_assigned_at,
  o.customer_block,
  o.merchant_id,
  o.customer_user_id
FROM customer_order o
WHERE o.id = :order_id;

-- 2) courier_assignment history for the order (open row has ended_at IS NULL).
SELECT
  ca.id            AS assignment_id,
  ca.order_id,
  ca.courier_user_id,
  ca.assignment_type,
  ca.status,
  ca.requested_at,
  ca.assigned_at,
  ca.responded_at,
  ca.ended_at,
  ca.ended_reason
FROM courier_assignment ca
WHERE ca.order_id = :order_id
ORDER BY ca.id DESC;

-- 3) ID ALIGNMENT: the crux of "assigned but invisible in the delivery app".
--    All *_user_id columns below MUST be the same number for a healthy order,
--    and that number is the value the delivery app authenticates with (JWT sub).
SELECT
  o.id                                   AS order_id,
  o.delivery_user_id                     AS order_delivery_user_id,
  ca.courier_user_id                     AS open_assignment_user_id,
  cp.user_id                             AS courier_profile_user_id,
  (o.delivery_user_id = ca.courier_user_id) AS order_matches_assignment,
  (o.delivery_user_id = cp.user_id)         AS order_matches_profile
FROM customer_order o
LEFT JOIN courier_assignment ca
       ON ca.order_id = o.id AND ca.ended_at IS NULL
LEFT JOIN courier_profile cp
       ON cp.user_id = o.delivery_user_id
WHERE o.id = :order_id;

-- 4) The assigned account: is it a real, enabled, online delivery account?
--    Any FALSE / stale value here explains why the app rejects or hides it.
SELECT
  u.id                                   AS user_id,
  u.role,
  u.delivery_account_approved            AS approved,
  (u.is_account_disabled = FALSE)        AS enabled,
  cp.driver_type,
  cp.availability_status,
  (LOWER(COALESCE(cp.availability_status,'online')) = 'online') AS manually_available,
  presence.is_online                     AS heartbeat_online,
  presence.updated_at                    AS heartbeat_at,
  (presence.updated_at >= NOW() - INTERVAL '90 seconds') AS heartbeat_fresh,
  EXISTS (SELECT 1 FROM taxi_captain_profile t WHERE t.user_id = u.id) AS is_taxi_captain,
  (SELECT COUNT(*) FROM customer_order a
     WHERE a.delivery_user_id = u.id
       AND a.delivery_assignment_status = 'ASSIGNED') AS active_assigned_orders
FROM customer_order o
JOIN app_user u ON u.id = o.delivery_user_id
LEFT JOIN courier_profile cp ON cp.user_id = u.id
LEFT JOIN LATERAL (
  SELECT p.is_online, p.updated_at
  FROM courier_presence p
  WHERE p.courier_user_id = u.id
  ORDER BY p.updated_at DESC
  LIMIT 1
) presence ON TRUE
WHERE o.id = :order_id;

-- 5) ELIGIBLE-DRIVER POOL AUDIT: every delivery account with a per-reason
--    verdict, so a zero pool is explained (wrongRole / unapproved / disabled /
--    taxiCaptain / manuallyUnavailable / offlineHeartbeat / busy).
SELECT
  u.id AS candidate_user_id,
  CASE
    WHEN u.role <> 'delivery'                       THEN 'wrongRole'
    WHEN u.delivery_account_approved IS NOT TRUE    THEN 'unapproved'
    WHEN u.is_account_disabled = TRUE               THEN 'disabled'
    WHEN EXISTS (SELECT 1 FROM taxi_captain_profile t WHERE t.user_id = u.id)
                                                    THEN 'taxiCaptain'
    WHEN cp.user_id IS NULL                         THEN 'noDeliveryProfile'
    WHEN LOWER(COALESCE(cp.availability_status,'online')) <> 'online'
                                                    THEN 'manuallyUnavailable'
    WHEN NOT EXISTS (
      SELECT 1 FROM courier_presence p
      WHERE p.courier_user_id = u.id
        AND p.is_online = TRUE
        AND p.updated_at >= NOW() - INTERVAL '90 seconds'
    )                                               THEN 'offlineHeartbeat'
    WHEN EXISTS (
      SELECT 1 FROM customer_order a
      WHERE a.delivery_user_id = u.id
        AND a.delivery_assignment_status = 'ASSIGNED'
    )                                               THEN 'busy'
    WHEN EXISTS (
      SELECT 1 FROM courier_assignment oa
      WHERE oa.courier_user_id = u.id AND oa.ended_at IS NULL
    )                                               THEN 'busyOpenAssignment'
    ELSE 'ELIGIBLE'
  END AS verdict,
  u.block AS user_block
FROM app_user u
LEFT JOIN courier_profile cp ON cp.user_id = u.id
WHERE u.role = 'delivery'
ORDER BY verdict, u.id;

-- 6) Rejection-reason rollup (mirrors the [delivery-auto-assign] backend log).
SELECT verdict, COUNT(*) AS accounts
FROM (
  SELECT
    CASE
      WHEN u.delivery_account_approved IS NOT TRUE THEN 'unapproved'
      WHEN u.is_account_disabled = TRUE            THEN 'disabled'
      WHEN EXISTS (SELECT 1 FROM taxi_captain_profile t WHERE t.user_id = u.id)
                                                   THEN 'taxiCaptain'
      WHEN cp.user_id IS NULL                      THEN 'noDeliveryProfile'
      WHEN LOWER(COALESCE(cp.availability_status,'online')) <> 'online'
                                                   THEN 'manuallyUnavailable'
      WHEN NOT EXISTS (
        SELECT 1 FROM courier_presence p
        WHERE p.courier_user_id = u.id AND p.is_online = TRUE
          AND p.updated_at >= NOW() - INTERVAL '90 seconds'
      )                                            THEN 'offlineHeartbeat'
      WHEN EXISTS (
        SELECT 1 FROM customer_order a
        WHERE a.delivery_user_id = u.id
          AND a.delivery_assignment_status = 'ASSIGNED'
      )                                            THEN 'busy'
      WHEN EXISTS (
        SELECT 1 FROM courier_assignment oa
        WHERE oa.courier_user_id = u.id AND oa.ended_at IS NULL
      )                                            THEN 'busyOpenAssignment'
      ELSE 'ELIGIBLE'
    END AS verdict
  FROM app_user u
  LEFT JOIN courier_profile cp ON cp.user_id = u.id
  WHERE u.role = 'delivery'
) rolled
GROUP BY verdict
ORDER BY accounts DESC;
