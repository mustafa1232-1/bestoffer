import { env } from "../../config/env.js";
import { expireInventoryReservationsBatch } from "./orders.repo.js";

let timer = null;
let running = false;

export function startInventoryReservationWorker() {
  if (timer) return;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      await expireInventoryReservationsBatch({ limit: 200 });
    } catch (error) {
      console.error("[orders] inventory reservation cleanup failed", error);
    } finally {
      running = false;
    }
  };
  void tick();
  timer = setInterval(tick, env.orderStockReservationCleanupIntervalMs || 60000);
  timer.unref?.();
}

export function stopInventoryReservationWorker() {
  if (!timer) return;
  clearInterval(timer);
  timer = null;
}
