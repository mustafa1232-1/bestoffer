/* eslint-disable no-console */
import "dotenv/config";

async function run() {
  console.log("[session-cleanup] disabled: sessions persist until explicit logout or account deletion.");
}

run().catch((error) => {
  console.error("[session-cleanup] failed:", error);
  process.exit(1);
});
