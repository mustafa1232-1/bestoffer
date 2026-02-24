import "dotenv/config";

import { ensureSchema } from "../config/db.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";

async function run() {
  await runSqlMigrations({ force: true });
  await ensureSchema();
  console.log("[migrate] SQL + ensureSchema completed.");
}

run().catch((error) => {
  console.error("[migrate] failed:", error);
  process.exit(1);
});
