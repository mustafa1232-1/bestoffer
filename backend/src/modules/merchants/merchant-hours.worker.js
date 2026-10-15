import { q } from "../../config/db.js";

const DEFAULT_INTERVAL_MS = 60_000;
const DEFAULT_TIME_ZONE = "Asia/Baghdad";

let workerTimer = null;
let workerRunPromise = null;

function nowParts(timeZone = DEFAULT_TIME_ZONE) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const hour = Number(parts.find((p) => p.type === "hour")?.value || 0);
  const minute = Number(parts.find((p) => p.type === "minute")?.value || 0);
  return { hour: hour % 24, minute };
}

function minutesFromClock(hour, minute) {
  return Number(hour) * 60 + Number(minute || 0);
}

export function parseMerchantWorkingHours(value) {
  const text = String(value || "").trim();
  if (!text) return null;
  const normalized = text
    .replace(/\u2013|\u2014/g, "-")
    .replace(/\bto\b/i, "-")
    .replace(/الى|إلى/g, "-");
  const match = normalized.match(
    /(\d{1,2})(?::(\d{2}))?\s*-\s*(\d{1,2})(?::(\d{2}))?/,
  );
  if (!match) return null;
  const openHour = Number(match[1]);
  const openMinute = Number(match[2] || 0);
  const closeHour = Number(match[3]);
  const closeMinute = Number(match[4] || 0);
  if (
    openHour < 0 ||
    openHour > 24 ||
    closeHour < 0 ||
    closeHour > 24 ||
    openMinute < 0 ||
    openMinute > 59 ||
    closeMinute < 0 ||
    closeMinute > 59
  ) {
    return null;
  }
  return {
    openMinuteOfDay: minutesFromClock(openHour % 24, openMinute),
    closeMinuteOfDay: minutesFromClock(closeHour % 24, closeMinute),
  };
}

export function isMerchantOpenForSchedule(schedule, parts = nowParts()) {
  if (!schedule) return null;
  const nowMinute = minutesFromClock(parts.hour, parts.minute);
  const open = schedule.openMinuteOfDay;
  const close = schedule.closeMinuteOfDay;
  if (open === close) return true;
  if (open < close) return nowMinute >= open && nowMinute < close;
  return nowMinute >= open || nowMinute < close;
}

export async function reconcileMerchantWorkingHours({
  timeZone = DEFAULT_TIME_ZONE,
} = {}) {
  const currentParts = nowParts(timeZone);
  const merchants = await q(
    `SELECT id, is_open, working_hours
     FROM merchant
     WHERE working_hours IS NOT NULL
       AND TRIM(working_hours) <> ''
       AND is_approved = TRUE
       AND COALESCE(is_disabled, FALSE) = FALSE`,
  );

  let checked = 0;
  let updated = 0;
  for (const merchant of merchants.rows) {
    const schedule = parseMerchantWorkingHours(merchant.working_hours);
    const shouldOpen = isMerchantOpenForSchedule(schedule, currentParts);
    if (shouldOpen == null) continue;
    checked += 1;
    if (merchant.is_open === shouldOpen) continue;
    await q(
      `UPDATE merchant
       SET is_open = $2, updated_at = NOW()
       WHERE id = $1
         AND COALESCE(is_open, FALSE) <> $2`,
      [Number(merchant.id), shouldOpen],
    );
    updated += 1;
  }
  return { checked, updated };
}

export function startMerchantHoursWorker({
  intervalMs = DEFAULT_INTERVAL_MS,
} = {}) {
  if (workerTimer) return true;
  const tick = () => {
    if (workerRunPromise) return;
    workerRunPromise = reconcileMerchantWorkingHours()
      .catch((error) => {
        console.error("[merchant-hours-worker] reconcile failed", error);
      })
      .finally(() => {
        workerRunPromise = null;
      });
  };
  tick();
  workerTimer = setInterval(tick, intervalMs);
  workerTimer.unref?.();
  return true;
}

export async function stopMerchantHoursWorker() {
  if (workerTimer) {
    clearInterval(workerTimer);
    workerTimer = null;
  }
  await workerRunPromise;
}
