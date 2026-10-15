import "dotenv/config";

import { q } from "../config/db.js";

const patterns = [
  "customer_order",
  "order_%",
  "delivery_%",
  "merchant_%ledger%",
  "merchant_%payment%",
  "merchant_%invoice%",
  "merchant_%settlement%",
  "merchant_%kpi%",
  "merchant_%stats%",
  "support_%",
  "taxi_%",
  "real_estate_%",
  "car_%",
  "service_%",
  "coupon_usage",
  "product_review",
  "app_notification",
];

const tables = await q(
  `SELECT table_name
     FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
      AND (${patterns.map((_, index) => `table_name LIKE $${index + 1}`).join(" OR ")})
    ORDER BY table_name`,
  patterns
);

const rows = [];
for (const table of tables.rows.map((row) => row.table_name)) {
  const count = await q(`SELECT COUNT(*)::int AS count FROM "${table}"`);
  rows.push({ table, count: Number(count.rows[0]?.count || 0) });
}

const userRoles = await q(
  `SELECT role, COUNT(*)::int AS count
     FROM app_user
    GROUP BY role
    ORDER BY role`
);

console.log(
  JSON.stringify(
    {
      userRoles: userRoles.rows,
      targetedTables: rows,
    },
    null,
    2
  )
);

process.exit(0);
