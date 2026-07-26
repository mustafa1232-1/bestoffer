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

export function computeDueDates(priority, createdAtMs) {
  const target = SLA_TARGETS[priority] || SLA_TARGETS.normal;
  return {
    firstResponseDueAt: new Date(
      createdAtMs + target.firstResponseMins * 60_000
    ).toISOString(),
    resolutionDueAt: new Date(
      createdAtMs + target.resolutionMins * 60_000
    ).toISOString(),
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
