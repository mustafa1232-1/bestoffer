/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

const orderId = Number(process.argv[2]);

if (!Number.isInteger(orderId) || orderId <= 0) {
  throw new Error("Usage: node src/scripts/diagnoseOrderDispatch.js <order-id>");
}

async function main() {
  const orderResult = await pool.query(
    `SELECT co.id,
            co.order_group_id,
            co.merchant_id,
            co.status,
            co.delivery_assignment_status,
            co.delivery_user_id,
            co.created_at,
            co.approved_at,
            co.courier_requested_at,
            co.courier_assigned_at,
            m.name AS merchant_name,
            m.owner_user_id,
            m.is_open AS merchant_is_open,
            m.is_approved AS merchant_is_approved,
            m.is_disabled AS merchant_is_disabled,
            COALESCE(u.is_account_disabled, FALSE) AS owner_is_disabled
       FROM customer_order co
       JOIN merchant m ON m.id = co.merchant_id
       LEFT JOIN app_user u ON u.id = m.owner_user_id
      WHERE co.id = $1`,
    [orderId]
  );
  const order = orderResult.rows[0];
  if (!order) {
    console.log(JSON.stringify({ orderId, found: false }, null, 2));
    return;
  }

  const [group, notifications, assignments, ownerSessions, ownerPushTokens] =
    await Promise.all([
      pool.query(
        `SELECT og.id AS order_group_id,
                og.status AS group_status,
                dj.id AS delivery_job_id,
                dj.assignment_status AS job_assignment_status,
                dj.lifecycle_status AS job_lifecycle_status,
                dj.delivery_user_id,
                dj.assignment_attempt_count,
                dj.created_at AS job_created_at,
                dj.updated_at AS job_updated_at,
                dps.pickup_status,
                dps.updated_at AS pickup_updated_at
           FROM order_group og
           LEFT JOIN delivery_job dj ON dj.order_group_id = og.id
           LEFT JOIN delivery_pickup_stop dps ON dps.delivery_job_id = dj.id
                                          AND dps.child_order_id = $1
          WHERE og.id = $2`,
        [orderId, Number(order.order_group_id || 0)]
      ),
      pool.query(
        `SELECT n.id,
                n.type,
                n.title,
                n.body,
                n.is_read,
                n.created_at,
                e.event_status,
                e.platform,
                e.error_code,
                e.created_at AS delivery_event_at
           FROM app_notification n
           LEFT JOIN notification_delivery_event e ON e.notification_id = n.id
          WHERE n.user_id = $1
            AND n.order_id = $2
          ORDER BY n.created_at ASC, e.created_at ASC`,
        [Number(order.owner_user_id), orderId]
      ),
      pool.query(
        `SELECT ca.id,
                ca.courier_user_id,
                ca.assignment_type,
                ca.status,
                ca.created_at,
                ca.responded_at,
                ca.ended_at,
                ca.ended_reason
           FROM courier_assignment ca
          WHERE ca.order_id = $1
             OR ca.delivery_job_id IN (
                  SELECT id FROM delivery_job WHERE order_group_id = $2
                )
          ORDER BY ca.created_at ASC`,
        [orderId, Number(order.order_group_id || 0)]
      ),
      pool.query(
        `SELECT COUNT(*) FILTER (
                  WHERE is_revoked = FALSE AND expires_at > NOW()
                )::int AS active_sessions,
                MAX(last_seen_at) AS latest_seen_at
           FROM user_session
          WHERE user_id = $1`,
        [Number(order.owner_user_id)]
      ),
      pool.query(
        `SELECT COUNT(*) FILTER (WHERE is_active)::int AS active_tokens,
                COUNT(*) FILTER (
                  WHERE is_active AND app_surface = 'store'
                )::int AS active_store_tokens,
                MAX(last_seen_at) AS latest_seen_at
           FROM user_push_token
          WHERE user_id = $1`,
        [Number(order.owner_user_id)]
      ),
    ]);

  console.log(
    JSON.stringify(
      {
        orderId,
        found: true,
        order,
        groupedDelivery: group.rows,
        merchantNotifications: notifications.rows,
        assignments: assignments.rows,
        ownerSessions: ownerSessions.rows[0],
        ownerPushTokens: ownerPushTokens.rows[0],
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
