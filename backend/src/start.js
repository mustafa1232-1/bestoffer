import cluster from "node:cluster";
import os from "node:os";

import { env } from "./config/env.js";

const runtime = String(
  process.env.APP_RUNTIME || process.env.SERVICE_RUNTIME || "app"
)
  .trim()
  .toLowerCase();

function resolveAutoWorkerCount() {
  const available =
    typeof os.availableParallelism === "function"
      ? os.availableParallelism()
      : (os.cpus() || []).length || 1;
  return Math.max(1, Math.min(available, env.appClusterMaxWorkers || 2));
}

function resolveDesiredWorkers() {
  if (runtime !== "app") return 1;
  const mode = String(env.appClusterMode || "off").trim().toLowerCase();
  if (mode === "off" || mode === "false" || mode === "0") return 1;
  if (mode === "auto" && !env.redisUrl) return 1;
  if (env.appWorkers > 0) return env.appWorkers;
  return resolveAutoWorkerCount();
}

async function startSingleProcess() {
  if (runtime === "ops" || runtime === "ai-ops" || runtime === "ai_ops") {
    await import("./ops-server.js");
  } else {
    await import("./server.js");
  }
}

function bootCluster() {
  const desiredWorkers = resolveDesiredWorkers();
  if (desiredWorkers <= 1 || !cluster.isPrimary) {
    process.env.APP_WORKERS_TOTAL = String(desiredWorkers);
    if (!process.env.APP_WORKER_SLOT) {
      process.env.APP_WORKER_SLOT = "0";
    }
    return startSingleProcess();
  }

  console.log(
    `[cluster] primary pid=${process.pid} runtime=${runtime} workers=${desiredWorkers}`
  );

  let nextWorkerSlot = 1;
  const workerSlots = new Map();
  const forkWorker = (slot = null) => {
    const workerSlot = slot ?? nextWorkerSlot;
    nextWorkerSlot = workerSlot >= desiredWorkers ? 1 : workerSlot + 1;
    const worker = cluster.fork({
      ...process.env,
      APP_WORKERS_TOTAL: String(desiredWorkers),
      APP_WORKER_SLOT: String(workerSlot),
    });
    workerSlots.set(worker.id, workerSlot);
    return worker;
  };

  for (let index = 0; index < desiredWorkers; index += 1) {
    forkWorker(index + 1);
  }

  cluster.on("exit", (worker, code, signal) => {
    console.warn(
      `[cluster] worker=${worker.process.pid} exited code=${code} signal=${signal || "none"}; restarting`
    );
    const previousSlot = Number(workerSlots.get(worker.id) || 0);
    workerSlots.delete(worker.id);
    forkWorker(previousSlot > 0 ? previousSlot : null);
  });
}

Promise.resolve(bootCluster()).catch((error) => {
  console.error("[start] failed to boot runtime:", error);
  process.exit(1);
});
