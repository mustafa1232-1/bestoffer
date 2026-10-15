import "dotenv/config";

import { pool, q } from "../config/db.js";

const TABLES = [
  "customer_order",
  "order_item",
  "order_status_history",
  "support_ticket",
  "support_ticket_event",
  "support_ticket_message",
  "courier_assignment",
  "delivery_day_archive",
  "taxi_ride_request",
  "taxi_captain_profile",
  "taxi_captain_presence",
  "service_provider_profiles",
  "service_offerings",
  "service_requests",
  "real_estate_listing",
  "car_listing",
  "inventory_reservation",
  "product",
  "product_media",
  "product_variant",
  "store_inventory_item",
  "merchant_category",
  "merchant_discovery_subcategory",
  "social_post",
  "social_post_comment",
  "social_post_comment_like",
  "social_post_like",
  "social_post_media",
  "social_post_report",
  "social_post_report_review_log",
  "social_post_stats",
  "social_story",
  "social_chat_message",
];

function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/.test(name)) {
    throw new Error(`Unsafe identifier: ${name}`);
  }
  return `"${name}"`;
}

async function countTable(table) {
  const result = await q(`SELECT COUNT(*)::int AS count FROM ${quoteIdent(table)}`);
  return Number(result.rows[0]?.count || 0);
}

async function main() {
  const tables = [];
  for (const table of TABLES) {
    tables.push({ table, count: await countTable(table) });
  }

  const roles = await q(
    `SELECT role, COUNT(*)::int AS count
       FROM app_user
      GROUP BY role
      ORDER BY role`
  );
  const removedUsers = await q(
    `SELECT id, phone, full_name, role
       FROM app_user
      WHERE phone = ANY($1::text[])
      ORDER BY phone`,
    [["07722773231", "07780000000", "07721234567"]]
  );

  console.log(
    JSON.stringify(
      {
        tables,
        roles: roles.rows,
        removedUsersStillPresent: removedUsers.rows,
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error("[verify-launch-clean] failed:", error?.message || error);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
