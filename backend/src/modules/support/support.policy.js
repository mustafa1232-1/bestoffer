/**
 * Purpose:
 * سياسة تذاكر الدعم النقية (المرحلة 4): الحالات، الانتقالات المسموحة، أهداف
 * SLA، وحساب حالة SLA (أخضر/أصفر/أحمر). بلا وصول لقاعدة البيانات — قابلة
 * للاختبار وحدةً ومعاد استخدامها في service.
 */

export const TICKET_DOMAINS = Object.freeze([
  "SHOPPING", "DELIVERY", "TAXI", "SERVICES", "REAL_ESTATE", "CARS",
  "JOBS", "COMMUNITY", "ACCOUNT", "PAYMENTS", "OTHER",
]);

export const TICKET_TYPES = Object.freeze([
  "PROBLEM", "COMPLAINT", "QUESTION", "SUGGESTION", "SAFETY", "REFUND", "OTHER",
]);

export const TICKET_PRIORITIES = Object.freeze(["low", "normal", "high", "urgent"]);

export const TICKET_STATUSES = Object.freeze([
  "NEW", "TRIAGED", "ASSIGNED", "IN_PROGRESS", "WAITING_FOR_CUSTOMER",
  "WAITING_FOR_MERCHANT", "WAITING_FOR_CAPTAIN", "WAITING_FOR_DELIVERY",
  "ESCALATED", "RESOLVED", "CLOSED", "REOPENED",
]);

export const TICKET_TERMINAL_STATUSES = Object.freeze(["CLOSED"]);

const WAITING = [
  "WAITING_FOR_CUSTOMER",
  "WAITING_FOR_MERCHANT",
  "WAITING_FOR_CAPTAIN",
  "WAITING_FOR_DELIVERY",
];

// أهداف SLA بالدقائق حسب الأولوية (قابلة للضبط لاحقاً حسب المجال/النوع).
export const SLA_TARGETS = Object.freeze({
  urgent: { firstResponseMins: 15, resolutionMins: 120 },
  high: { firstResponseMins: 60, resolutionMins: 480 },
  normal: { firstResponseMins: 240, resolutionMins: 1440 },
  low: { firstResponseMins: 480, resolutionMins: 4320 },
});

// خريطة الانتقالات المسموحة (state machine).
export const ALLOWED_TRANSITIONS = Object.freeze({
  NEW: ["TRIAGED", "ASSIGNED", "IN_PROGRESS", "ESCALATED", "CLOSED"],
  TRIAGED: ["ASSIGNED", "IN_PROGRESS", "ESCALATED", "CLOSED"],
  ASSIGNED: ["IN_PROGRESS", ...WAITING, "ESCALATED", "RESOLVED", "CLOSED"],
  IN_PROGRESS: [...WAITING, "ESCALATED", "RESOLVED", "CLOSED"],
  WAITING_FOR_CUSTOMER: ["IN_PROGRESS", "RESOLVED", "ESCALATED", "CLOSED"],
  WAITING_FOR_MERCHANT: ["IN_PROGRESS", "RESOLVED", "ESCALATED", "CLOSED"],
  WAITING_FOR_CAPTAIN: ["IN_PROGRESS", "RESOLVED", "ESCALATED", "CLOSED"],
  WAITING_FOR_DELIVERY: ["IN_PROGRESS", "RESOLVED", "ESCALATED", "CLOSED"],
  ESCALATED: ["ASSIGNED", "IN_PROGRESS", "RESOLVED", "CLOSED"],
  RESOLVED: ["CLOSED", "REOPENED"],
  CLOSED: ["REOPENED"],
  REOPENED: ["ASSIGNED", "IN_PROGRESS", ...WAITING, "ESCALATED", "RESOLVED", "CLOSED"],
});

export function isValidDomain(d) {
  return TICKET_DOMAINS.includes(String(d || ""));
}
export function isValidType(t) {
  return TICKET_TYPES.includes(String(t || ""));
}
export function isValidPriority(p) {
  return TICKET_PRIORITIES.includes(String(p || ""));
}
export function isTerminalStatus(s) {
  return TICKET_TERMINAL_STATUSES.includes(String(s || ""));
}

export function canTransition(from, to) {
  const next = ALLOWED_TRANSITIONS[String(from || "")];
  return Array.isArray(next) && next.includes(String(to || ""));
}

function normalizeBusinessHours(options = {}) {
  if (!options || options.enabled !== true) return null;
  const startHour = Number(options.startHour ?? 9);
  const endHour = Number(options.endHour ?? 21);
  if (!Number.isInteger(startHour) || !Number.isInteger(endHour)) return null;
  if (startHour < 0 || startHour > 23 || endHour < 1 || endHour > 24) return null;
  if (endHour <= startHour) return null;
  const timezoneOffsetMinutes = Number(options.timezoneOffsetMinutes ?? 180);
  const rawWorkdays = options.workdays instanceof Set
    ? [...options.workdays]
    : Array.isArray(options.workdays)
    ? options.workdays
    : [0, 1, 2, 3, 4, 5, 6];
  const workdays = new Set(
    rawWorkdays
      .map((day) => Number(day))
      .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6)
  );
  if (workdays.size === 0) return null;
  return { enabled: true, startHour, endHour, timezoneOffsetMinutes, workdays };
}

function localParts(utcMs, timezoneOffsetMinutes) {
  const d = new Date(utcMs + timezoneOffsetMinutes * 60_000);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth(),
    date: d.getUTCDate(),
    day: d.getUTCDay(),
    hour: d.getUTCHours(),
  };
}

function localDayBoundaryUtcMs(parts, hour, timezoneOffsetMinutes) {
  return Date.UTC(parts.year, parts.month, parts.date, hour, 0, 0, 0)
    - timezoneOffsetMinutes * 60_000;
}

function nextLocalDayStartUtcMs(utcMs, business) {
  const parts = localParts(utcMs, business.timezoneOffsetMinutes);
  return Date.UTC(parts.year, parts.month, parts.date + 1, business.startHour, 0, 0, 0)
    - business.timezoneOffsetMinutes * 60_000;
}

function alignToBusinessWindow(utcMs, business) {
  let cursor = utcMs;
  for (let guard = 0; guard < 370; guard += 1) {
    const parts = localParts(cursor, business.timezoneOffsetMinutes);
    const startMs = localDayBoundaryUtcMs(
      parts,
      business.startHour,
      business.timezoneOffsetMinutes
    );
    const endMs = localDayBoundaryUtcMs(
      parts,
      business.endHour,
      business.timezoneOffsetMinutes
    );
    if (!business.workdays.has(parts.day)) {
      cursor = nextLocalDayStartUtcMs(cursor, business);
      continue;
    }
    if (cursor < startMs) return startMs;
    if (cursor >= endMs) {
      cursor = nextLocalDayStartUtcMs(cursor, business);
      continue;
    }
    return cursor;
  }
  return utcMs;
}

export function addBusinessMinutes(startAtMs, minutes, businessOptions = {}) {
  const business = normalizeBusinessHours(businessOptions);
  if (!business) return startAtMs + Number(minutes || 0) * 60_000;
  let remainingMs = Math.max(0, Number(minutes || 0)) * 60_000;
  let cursor = alignToBusinessWindow(Number(startAtMs), business);
  while (remainingMs > 0) {
    const parts = localParts(cursor, business.timezoneOffsetMinutes);
    const endMs = localDayBoundaryUtcMs(
      parts,
      business.endHour,
      business.timezoneOffsetMinutes
    );
    const availableMs = Math.max(0, endMs - cursor);
    if (remainingMs <= availableMs) return cursor + remainingMs;
    remainingMs -= availableMs;
    cursor = alignToBusinessWindow(nextLocalDayStartUtcMs(cursor, business), business);
  }
  return cursor;
}

export function computeDueDates(priority, createdAtMs, options = {}) {
  const target = SLA_TARGETS[priority] || SLA_TARGETS.normal;
  const businessHours = normalizeBusinessHours(options.businessHours);
  const addMinutes = (minutes) =>
    businessHours
      ? addBusinessMinutes(createdAtMs, minutes, businessHours)
      : createdAtMs + minutes * 60_000;
  return {
    firstResponseDueAt: new Date(addMinutes(target.firstResponseMins)).toISOString(),
    resolutionDueAt: new Date(addMinutes(target.resolutionMins)).toISOString(),
  };
}

// عتبة الاقتراب من التجاوز: ضمن آخر 20% من النافذة = أصفر.
function slaLevel(dueAtMs, satisfiedAtMs, nowMs, windowMs) {
  if (satisfiedAtMs != null) {
    return satisfiedAtMs <= dueAtMs ? "met" : "breached";
  }
  if (nowMs > dueAtMs) return "red";
  const remaining = dueAtMs - nowMs;
  if (windowMs > 0 && remaining <= windowMs * 0.2) return "yellow";
  return "green";
}

/**
 * يحسب حالة SLA للردّ الأول والحل.
 */
export function computeSlaState({
  status,
  createdAtMs,
  firstResponseDueAtMs,
  resolutionDueAtMs,
  firstResponseAtMs = null,
  resolvedAtMs = null,
  nowMs,
}) {
  const terminalResolved =
    status === "RESOLVED" || status === "CLOSED";
  const frWindow =
    firstResponseDueAtMs != null && createdAtMs != null
      ? firstResponseDueAtMs - createdAtMs
      : 0;
  const resWindow =
    resolutionDueAtMs != null && createdAtMs != null
      ? resolutionDueAtMs - createdAtMs
      : 0;

  return {
    firstResponse:
      firstResponseDueAtMs == null
        ? "none"
        : slaLevel(firstResponseDueAtMs, firstResponseAtMs, nowMs, frWindow),
    resolution:
      resolutionDueAtMs == null
        ? "none"
        : slaLevel(
            resolutionDueAtMs,
            terminalResolved ? resolvedAtMs ?? nowMs : resolvedAtMs,
            nowMs,
            resWindow
          ),
  };
}
