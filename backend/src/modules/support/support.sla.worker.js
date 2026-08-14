import { processSupportSlaBatch } from "./support.service.js";

let workerTimer = null;
let workerRunPromise = null;

function workerConfig() {
  return {
    intervalMs: Math.max(
      15_000,
      Math.min(10 * 60_000, Number(process.env.SUPPORT_SLA_WORKER_INTERVAL_MS) || 60_000)
    ),
    batchSize: Math.max(
      1,
      Math.min(200, Number(process.env.SUPPORT_SLA_WORKER_BATCH_SIZE) || 50)
    ),
    warningWithinMinutes: Math.max(
      1,
      Math.min(240, Number(process.env.SUPPORT_SLA_WARNING_MINUTES) || 30)
    ),
  };
}

export async function processSupportSlaWorkerBatch(options = {}) {
  return processSupportSlaBatch(options);
}

export function startSupportSlaWorker() {
  if (workerTimer) return true;
  const { intervalMs, batchSize, warningWithinMinutes } = workerConfig();
  workerTimer = setInterval(() => {
    if (workerRunPromise) return;
    workerRunPromise = processSupportSlaBatch({
      limit: batchSize,
      warningWithinMinutes,
    })
      .catch((error) => {
        console.error("[support-sla-worker] scheduled batch failed", error);
      })
      .finally(() => {
        workerRunPromise = null;
      });
  }, intervalMs);
  workerTimer.unref?.();
  processSupportSlaBatch({ limit: batchSize, warningWithinMinutes }).catch((error) => {
    console.error("[support-sla-worker] startup batch failed", error);
  });
  return true;
}

export async function stopSupportSlaWorker() {
  if (workerTimer) {
    clearInterval(workerTimer);
    workerTimer = null;
  }
  await workerRunPromise;
  workerRunPromise = null;
}
