import "dotenv/config";

import { q } from "../config/db.js";

const tables = await q(
  `SELECT table_name
     FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
    ORDER BY table_name`
);

const rows = [];
for (const table of tables.rows.map((row) => row.table_name)) {
  const count = await q(`SELECT COUNT(*)::int AS count FROM "${table}"`);
  const value = Number(count.rows[0]?.count || 0);
  if (value > 0) rows.push({ table, count: value });
}

console.log(JSON.stringify(rows, null, 2));
process.exit(0);
