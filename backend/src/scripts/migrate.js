import "dotenv/config";

import { ensureSchema, pool } from "../config/db.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { seedBuiltinStoreActivityDefinitions } from "../modules/merchants/store-activity.registry.js";

async function run() {
  await runSqlMigrations({ force: true });
  await ensureSchema();
  await seedBuiltinStoreActivityDefinitions();
  console.log("[migrate] SQL + ensureSchema + activity seed completed.");
}

run()
  .catch((error) => {
    console.error("[migrate] failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    // This file is also spawned by the test-database preparer. Closing the pool
    // is required so a successful migration terminates deterministically.
    await pool.end().catch((error) => {
      console.error("[migrate] failed to close database pool:", error);
      process.exitCode = 1;
    });
  });
