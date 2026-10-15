/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    search: String(process.env.DIAGNOSE_MERCHANT_SEARCH || "").trim(),
  };
  const positional = [];
  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--search" && next) {
      out.search = next;
      i += 1;
      continue;
    }
    if (!key.startsWith("--")) positional.push(key);
  }
  if (!out.search && positional.length) out.search = positional.join(" ");
  if (!out.search) out.search = "علوة مسلكي";
  return out;
}

async function main() {
  const { search } = parseArgs();
  const client = await pool.connect();
  try {
    const merchants = await client.query(
      `SELECT
         m.id,
         m.name,
         m.owner_user_id,
         m.is_open,
         m.is_approved,
         m.is_disabled,
         m.approval_status,
         u.phone AS owner_phone,
         u.full_name AS owner_name,
         u.role AS owner_role,
         COALESCE(u.is_account_disabled, FALSE) AS owner_disabled,
         u.locked_until,
         u.must_change_pin
       FROM merchant m
       LEFT JOIN app_user u ON u.id = m.owner_user_id
       WHERE m.name ILIKE $1
       ORDER BY m.id ASC
       LIMIT 20`,
      [`%${search}%`]
    );

    console.log(`[merchant-orders-diagnose] search="${search}" matches=${merchants.rowCount}`);
    for (const merchant of merchants.rows) {
      console.log(
        `[merchant] id=${merchant.id} name="${merchant.name}" owner=${merchant.owner_user_id || ""} phone=${merchant.owner_phone || ""} open=${merchant.is_open} approved=${merchant.is_approved} disabled=${merchant.is_disabled} owner_disabled=${merchant.owner_disabled} must_change_pin=${merchant.must_change_pin}`
      );

      const orderStats = await client.query(
        `SELECT
           COUNT(*)::int AS total_orders,
           COUNT(*) FILTER (
             WHERE status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')
           )::int AS non_cancelled,
           COUNT(*) FILTER (
             WHERE status IN ('pending','approved','preparing','ready_for_delivery','courier_requested')
           )::int AS current_like,
           MAX(created_at) AS last_order_at
         FROM customer_order
         WHERE merchant_id = $1`,
        [Number(merchant.id)]
      );
      const stats = orderStats.rows[0] || {};
      console.log(
        `[orders] total=${stats.total_orders || 0} non_cancelled=${stats.non_cancelled || 0} current_like=${stats.current_like || 0} last=${stats.last_order_at || ""}`
      );

      const latestOrders = await client.query(
        `SELECT id, status::text AS status, total_amount, created_at, customer_phone
         FROM customer_order
         WHERE merchant_id = $1
         ORDER BY id DESC
         LIMIT 10`,
        [Number(merchant.id)]
      );
      for (const order of latestOrders.rows) {
        console.log(
          `[order] id=${order.id} status=${order.status} total=${order.total_amount} created=${order.created_at} customer=${order.customer_phone || ""}`
        );
      }

      const notifications = await client.query(
        `SELECT type, COUNT(*)::int AS count, MAX(created_at) AS last_at
         FROM app_notification
         WHERE merchant_id = $1
           AND user_id = $2
         GROUP BY type
         ORDER BY last_at DESC`,
        [Number(merchant.id), Number(merchant.owner_user_id || 0)]
      );
      for (const row of notifications.rows) {
        console.log(`[notifications] type=${row.type} count=${row.count} last=${row.last_at}`);
      }

      const sessions = await client.query(
        `SELECT
           COUNT(*) FILTER (WHERE is_revoked = FALSE AND expires_at > NOW())::int AS active_sessions,
           COUNT(*) FILTER (WHERE is_revoked = TRUE)::int AS revoked_sessions,
           MAX(last_seen_at) AS last_seen_at
         FROM user_session
         WHERE user_id = $1`,
        [Number(merchant.owner_user_id || 0)]
      );
      const sessionStats = sessions.rows[0] || {};
      console.log(
        `[sessions] active=${sessionStats.active_sessions || 0} revoked=${sessionStats.revoked_sessions || 0} last_seen=${sessionStats.last_seen_at || ""}`
      );

      const pushTokens = await client.query(
        `SELECT
           COUNT(*) FILTER (WHERE is_active = TRUE)::int AS active_tokens,
           COUNT(*) FILTER (WHERE is_active = TRUE AND app_surface = 'store')::int AS active_store_tokens,
           MAX(last_seen_at) AS last_token_seen_at
         FROM user_push_token
         WHERE user_id = $1`,
        [Number(merchant.owner_user_id || 0)]
      );
      const tokenStats = pushTokens.rows[0] || {};
      console.log(
        `[push] active=${tokenStats.active_tokens || 0} store=${tokenStats.active_store_tokens || 0} last=${tokenStats.last_token_seen_at || ""}`
      );
    }
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[merchant-orders-diagnose] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
