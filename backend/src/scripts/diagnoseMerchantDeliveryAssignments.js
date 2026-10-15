/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

function parseArgs() {
  const search = process.argv.slice(2).join(" ").trim();
  return search || "علوة مسلكي";
}

async function main() {
  const search = parseArgs();
  const orders = await pool.query(
    `SELECT
       o.id,
       o.status::text AS status,
       o.delivery_assignment_status,
       o.delivery_user_id,
       o.assigned_by_store,
       o.courier_source,
       o.delivery_type,
       o.is_merchant_delivery,
       o.courier_requested_at,
       o.courier_assigned_at,
       o.approved_at,
       o.preparing_started_at,
       o.ready_for_pickup_at,
       o.updated_at,
       o.customer_phone,
       m.id AS merchant_id,
       m.name AS merchant_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE m.name ILIKE $1
     ORDER BY o.id DESC`,
    [`%${search}%`]
  );
  console.log(`[delivery-diagnose] search="${search}" orders=${orders.rowCount}`);
  for (const row of orders.rows) {
    console.log(JSON.stringify(row));
  }

  const ids = orders.rows.map((row) => Number(row.id)).filter((id) => id > 0);
  if (!ids.length) return;

  const assignments = await pool.query(
    `SELECT
       ca.id,
       ca.order_id,
       ca.courier_user_id,
       ca.status,
       ca.created_at,
       ca.assigned_at,
       ca.acknowledged_at,
       ca.responded_at,
       ca.ended_at,
       ca.ended_reason,
       ca.expires_at,
       u.full_name AS courier_name,
       u.phone AS courier_phone
     FROM courier_assignment ca
     LEFT JOIN app_user u ON u.id = ca.courier_user_id
     WHERE ca.order_id = ANY($1::bigint[])
     ORDER BY ca.order_id DESC, ca.id DESC`,
    [ids]
  );
  console.log(`[delivery-diagnose] assignments=${assignments.rowCount}`);
  for (const row of assignments.rows) {
    console.log(JSON.stringify(row));
  }

  const couriers = await pool.query(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       COALESCE(u.is_account_disabled, FALSE) AS disabled,
       u.delivery_account_approved,
       dp.availability_status,
       dp.coverage_block,
       p.is_online,
       p.updated_at AS presence_updated_at,
       EXISTS (
         SELECT 1 FROM courier_assignment ca
         WHERE ca.courier_user_id = u.id
           AND ca.ended_at IS NULL
       ) AS has_open_assignment
     FROM app_user u
     LEFT JOIN courier_profile dp ON dp.user_id = u.id
     LEFT JOIN courier_presence p ON p.courier_user_id = u.id
     WHERE u.role = 'delivery'
     ORDER BY u.id ASC
     LIMIT 50`
  );
  console.log(`[delivery-diagnose] couriers=${couriers.rowCount}`);
  for (const row of couriers.rows) {
    console.log(JSON.stringify(row));
  }
}

main()
  .catch((error) => {
    console.error(`[delivery-diagnose] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
