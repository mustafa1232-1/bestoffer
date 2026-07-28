import "dotenv/config";

import { ensureSchema } from "../config/db.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { seedBuiltinStoreActivityDefinitions } from "../modules/merchants/store-activity.registry.js";

async function run() {
  await runSqlMigrations({ force: true });
  await ensureSchema();
  await seedBuiltinStoreActivityDefinitions();
  console.log("[migrate] SQL + ensureSchema + activity seed completed.");
}

run().catch((error) => {
  console.error("[migrate] failed:", error);
  process.exit(1);
});
