/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

const CONFIRM_TOKEN = "RESTORE_EXPIRED_MERCHANT_ORDERS";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    search: "",
    all: args.includes("--all"),
    execute: args.includes("--execute"),
    confirm: "",
    hours: 24,
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
    if (key === "--confirm" && next) {
      out.confirm = next;
      i += 1;
      continue;
    }
    if (key === "--hours" && next) {
      const parsed = Number(next);
      out.hours = Number.isFinite(parsed) && parsed > 0 ? parsed : out.hours;
      i += 1;
      continue;
    }
    if (!key.startsWith("--")) positional.push(key);
  }
  if (!out.search && positional.length) out.search = positional.join(" ");
  if (out.all) return out;
  if (!out.search) out.search = "علوة مسلكي";
  return out;
}

async function main() {
  const options = parseArgs();
  const client = await pool.connect();
  try {
    const merchantFilter = options.all ? "" : "AND m.name ILIKE $1";
    const params = options.all
      ? [Number(options.hours)]
      : [`%${options.search}%`, Number(options.hours)];
    const hoursParam = options.all ? "$1" : "$2";
    const preview = await client.query(
      `SELECT o.id, o.status::text AS status, o.created_at, m.id AS merchant_id, m.name
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE 1 = 1
         ${merchantFilter}
         AND o.status = 'expired'
         AND o.created_at >= NOW() - (${hoursParam} * interval '1 hour')
       ORDER BY o.id DESC`,
      params
    );
    console.log(
      `[restore-expired-orders] search="${options.all ? "<all>" : options.search}" candidates=${preview.rowCount} hours=${options.hours}`
    );
    for (const row of preview.rows) {
      console.log(
        `[restore-expired-orders] order=${row.id} merchant=${row.merchant_id} name="${row.name}" created=${row.created_at}`
      );
    }
    if (!options.execute) {
      console.log(
        "[restore-expired-orders] dry-run only. Add --execute --confirm RESTORE_EXPIRED_MERCHANT_ORDERS to update."
      );
      return;
    }
    if (options.confirm !== CONFIRM_TOKEN) {
      throw new Error(`Missing --confirm ${CONFIRM_TOKEN}`);
    }

    const ids = preview.rows.map((row) => Number(row.id)).filter((id) => id > 0);
    if (!ids.length) {
      console.log("[restore-expired-orders] no orders to restore.");
      return;
    }
    const restored = await client.query(
      `UPDATE customer_order
       SET status = 'pending'::order_status,
           updated_at = NOW()
       WHERE id = ANY($1::bigint[])
         AND status = 'expired'
       RETURNING id`,
      [ids]
    );
    console.log(`[restore-expired-orders] restored=${restored.rowCount || 0}`);
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[restore-expired-orders] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
