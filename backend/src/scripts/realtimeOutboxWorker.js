import "dotenv/config";

import { validateRuntimeEnv } from "../config/env.js";
import {
  processRealtimeOutboxBatch,
  startRealtimeOutboxPump,
  stopRealtimeOutboxPump,
} from "../shared/realtime/realtime-outbox.js";

let shuttingDown = false;

async function shutdown(reason, exitCode = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.warn(`[realtime-outbox-worker] shutdown reason=${reason}`);
  await stopRealtimeOutboxPump().catch(() => {});
  process.exit(exitCode);
}

process.on("SIGINT", () => {
  void shutdown("SIGINT", 0);
});
process.on("SIGTERM", () => {
  void shutdown("SIGTERM", 0);
});

async function main() {
  validateRuntimeEnv();
  await processRealtimeOutboxBatch({ limit: 100 });
  const started = startRealtimeOutboxPump();
  if (!started) {
    console.warn(
      "[realtime-outbox-worker] Supabase realtime disabled or not configured. Exiting."
    );
    process.exit(0);
  }
  console.log("[realtime-outbox-worker] started");
}

main().catch((error) => {
  console.error("[realtime-outbox-worker] failed", error);
  process.exit(1);
});
