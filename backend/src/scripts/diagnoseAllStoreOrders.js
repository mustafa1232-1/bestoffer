/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

const CURRENT_STATUSES = [
  "pending",
  "approved",
  "preparing",
  "ready_for_delivery",
  "courier_requested",
  "on_the_way",
  "arrived",
];

async function printRows(label, rows) {
  console.log(`\n[${label}] rows=${rows.length}`);
  for (const row of rows) {
    console.log(JSON.stringify(row));
  }
}

async function main() {
  const client = await pool.connect();
  try {
    const statusCounts = await client.query(
      `SELECT status::text AS status,
              COUNT(*)::int AS count,
              MAX(created_at) AS last_at
       FROM customer_order
       GROUP BY status
       ORDER BY count DESC, status ASC`
    );
    await printRows("status_counts_all_time", statusCounts.rows);

    const recentStatusCounts = await client.query(
      `SELECT status::text AS status,
              COUNT(*)::int AS count,
              MAX(created_at) AS last_at
       FROM customer_order
       WHERE created_at >= NOW() - interval '24 hours'
       GROUP BY status
       ORDER BY count DESC, status ASC`
    );
    await printRows("status_counts_24h", recentStatusCounts.rows);

    const currentByMerchant = await client.query(
      `SELECT m.id AS merchant_id,
              m.name AS merchant_name,
              m.owner_user_id,
              COUNT(o.id)::int AS current_orders,
              MAX(o.created_at) AS last_current_at
       FROM merchant m
       LEFT JOIN customer_order o
         ON o.merchant_id = m.id
        AND o.status::text = ANY($1::text[])
        AND NOT (o.status = 'delivered' AND o.customer_confirmed_at IS NOT NULL)
       GROUP BY m.id, m.name, m.owner_user_id
       HAVING COUNT(o.id) > 0
       ORDER BY current_orders DESC, last_current_at DESC
       LIMIT 50`,
      [CURRENT_STATUSES]
    );
    await printRows("stores_with_current_orders", currentByMerchant.rows);

    const currentOwnerVisibility = await client.query(
      `SELECT COUNT(o.id)::int AS visible_to_owner_route
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE m.owner_user_id IS NOT NULL
         AND o.status::text = ANY($1::text[])
         AND NOT (o.status = 'delivered' AND o.customer_confirmed_at IS NOT NULL)`,
      [CURRENT_STATUSES]
    );
    await printRows("owner_route_visibility_total", currentOwnerVisibility.rows);

    const recentOrders = await client.query(
      `SELECT o.id,
              o.status::text AS status,
              o.created_at,
              o.customer_confirmed_at,
              m.id AS merchant_id,
              m.name AS merchant_name,
              m.owner_user_id,
              u.phone AS owner_phone
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       LEFT JOIN app_user u ON u.id = m.owner_user_id
       WHERE o.created_at >= NOW() - interval '24 hours'
       ORDER BY o.id DESC
       LIMIT 50`
    );
    await printRows("recent_orders_24h", recentOrders.rows);

    const employeesWithCurrent = await client.query(
      `SELECT ep.employee_user_id,
              u.phone,
              COUNT(o.id)::int AS current_orders_for_employee_merchants,
              ARRAY_AGG(DISTINCT m.id ORDER BY m.id) AS merchant_ids
       FROM merchant_employee_profile ep
       JOIN app_user u ON u.id = ep.employee_user_id
       JOIN merchant m ON m.id = ep.merchant_id
       JOIN customer_order o ON o.merchant_id = m.id
       WHERE ep.is_active = TRUE
         AND ep.archived_at IS NULL
         AND COALESCE(u.is_account_disabled, FALSE) = FALSE
         AND o.status::text = ANY($1::text[])
         AND NOT (o.status = 'delivered' AND o.customer_confirmed_at IS NOT NULL)
       GROUP BY ep.employee_user_id, u.phone
       ORDER BY current_orders_for_employee_merchants DESC
       LIMIT 30`,
      [CURRENT_STATUSES]
    );
    await printRows("active_employees_with_current_orders", employeesWithCurrent.rows);
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[diagnose-all-store-orders] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
