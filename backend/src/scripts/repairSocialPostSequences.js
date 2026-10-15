import "dotenv/config";

import { pool, q } from "../config/db.js";

const TABLES = [
  "social_post",
  "social_post_media",
  "social_post_comment",
  "social_post_report",
  "social_post_report_review_log",
];

function quoteLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/.test(name)) {
    throw new Error(`Unsafe identifier: ${name}`);
  }
  return `"${name}"`;
}

async function main() {
  const repaired = [];
  for (const table of TABLES) {
    const seq = await q(`SELECT pg_get_serial_sequence($1, 'id') AS seq`, [table]);
    const sequenceName = seq.rows[0]?.seq;
    if (!sequenceName) continue;
    const result = await q(
      `SELECT setval(${quoteLiteral(sequenceName)}, COALESCE((SELECT MAX(id) FROM ${quoteIdent(table)}), 1), true) AS value`
    );
    repaired.push({ table, sequenceName, value: result.rows[0]?.value });
  }
  console.log(JSON.stringify({ repaired }, null, 2));
}

main()
  .catch((error) => {
    console.error("[repair-social-post-sequences] failed:", error?.message || error);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
