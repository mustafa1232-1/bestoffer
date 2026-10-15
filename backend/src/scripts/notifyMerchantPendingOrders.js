/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { createManyNotifications } from "../modules/notifications/notifications.repo.js";
import { listActiveMerchantNotificationRecipients } from "../modules/owner/owner.repo.js";

const CONFIRM_TOKEN = "NOTIFY_MERCHANT_PENDING_ORDERS";

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    search: String(process.env.MERCHANT_SEARCH || "").trim(),
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
  if (!out.search) {
    throw new Error("Missing merchant search. Pass --search <merchant name>.");
  }
  return out;
}

function notificationKey(row) {
  return `${Number(row.userId)}:${Number(row.orderId)}`;
}

async function listCompanyRecipients(client, merchantId) {
  const result = await client.query(
    `SELECT cu.user_id AS user_id
     FROM merchant m
     JOIN company_user cu ON cu.company_id = m.company_id
     WHERE m.id = $1
       AND m.company_id IS NOT NULL
       AND cu.is_active = TRUE
       AND cu.role IN ('company_owner', 'company_manager', 'operations_viewer')`,
    [Number(merchantId)]
  );
  return result.rows.map((row) => ({ userId: Number(row.user_id) }));
}

async function buildNotifications(client, order) {
  const recipients = [];
  if (Number(order.owner_user_id || 0) > 0) {
    recipients.push({ userId: Number(order.owner_user_id) });
  }
  recipients.push(
    ...(await listActiveMerchantNotificationRecipients({
      merchantId: Number(order.merchant_id),
      requiredPermissions: ["view_orders", "accept_orders", "prepare_orders"],
    }))
  );
  recipients.push(...(await listCompanyRecipients(client, Number(order.merchant_id))));

  const seen = new Set();
  return recipients
    .map((recipient) => ({
      userId: Number(recipient.userId),
      type: "owner_new_order",
      title: "طلب جديد",
      body: `طلب جديد رقم #${order.id} لدى ${order.merchant_name}`,
      orderId: Number(order.id),
      merchantId: Number(order.merchant_id),
      payload: {
        orderId: Number(order.id),
        status: String(order.status || "pending"),
        requiresAction: true,
        target: "merchant_order_details",
      },
    }))
    .filter((row) => {
      if (!Number.isInteger(row.userId) || row.userId <= 0) return false;
      const key = notificationKey(row);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

async function main() {
  const options = parseArgs();
  const client = await pool.connect();
  try {
    const orders = await client.query(
      `SELECT
         o.id,
         o.status::text AS status,
         o.created_at,
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.owner_user_id
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE m.name ILIKE $1
         AND o.status IN ('pending','approved','preparing','ready_for_delivery','courier_requested')
         AND o.created_at >= NOW() - ($2 * interval '1 hour')
       ORDER BY o.id DESC`,
      [`%${options.search}%`, Number(options.hours)]
    );

    console.log(
      `[notify-pending-orders] search="${options.search}" orders=${orders.rowCount} hours=${options.hours}`
    );

    const notifications = [];
    for (const order of orders.rows) {
      const orderNotifications = await buildNotifications(client, order);
      console.log(
        `[notify-pending-orders] order=${order.id} merchant=${order.merchant_id} recipients=${orderNotifications.length}`
      );
      notifications.push(...orderNotifications);
    }

    if (!options.execute) {
      console.log(
        "[notify-pending-orders] dry-run only. Add --execute --confirm NOTIFY_MERCHANT_PENDING_ORDERS to send."
      );
      return;
    }
    if (options.confirm !== CONFIRM_TOKEN) {
      throw new Error(`Missing --confirm ${CONFIRM_TOKEN}`);
    }

    const created = await createManyNotifications(notifications);
    console.log(`[notify-pending-orders] notifications_created=${created.length}`);
    if (created.length > 0) {
      await delay(1500);
    }
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[notify-pending-orders] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
