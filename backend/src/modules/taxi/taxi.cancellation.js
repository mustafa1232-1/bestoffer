/**
 * Purpose:
 * سياسة قفل إلغاء رحلة التاكسي (المرحلة 1). دوال نقية بلا وصول لقاعدة البيانات
 * حتى يمكن اختبارها وحدةً وإعادة استخدامها في repo و service معاً.
 *
 * القاعدة:
 * - الإلغاء العادي مسموح فقط حتى `captain_assigned` (بعد القبول وقبل التوجه).
 * - من `captain_arriving` (التوجه إلى الزبون) فصاعداً: مقفول للطرفين.
 * - يبقى مسار الطوارئ + الإلغاء الطارئ الإداري متاحاً بعد القفل.
 */

export const TAXI_TERMINAL_STATUSES = Object.freeze([
  "completed",
  "cancelled",
  "expired",
]);

// الزبون يستطيع الإلغاء العادي في هذه الحالات فقط.
export const TAXI_CUSTOMER_CANCELLABLE_STATUSES = Object.freeze([
  "searching",
  "price_raise_required",
  "captain_assigned",
]);

// الكابتن يستطيع الإلغاء فقط بعد أن تُسنَد إليه الرحلة وقبل التوجه.
export const TAXI_CAPTAIN_CANCELLABLE_STATUSES = Object.freeze([
  "captain_assigned",
]);

// حالات نشطة لكن مقفولة أمام الإلغاء العادي (يبقى مخرج الطوارئ متاحاً).
export const TAXI_CANCELLATION_LOCKED_STATUSES = Object.freeze([
  "captain_arriving",
  "ride_started",
]);

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase();
}

/**
 * هل الرحلة مقفولة أمام الإلغاء العادي في حالتها الحالية؟
 */
export function isTaxiCancellationLocked(status) {
  return TAXI_CANCELLATION_LOCKED_STATUSES.includes(normalizeStatus(status));
}

/**
 * يقرّر ما إذا كان بإمكان الطرف تنفيذ إلغاء عادي على رحلة بحالتها الحالية.
 * لا يرمي استثناءً أبداً؛ يُعيد كائن قرار.
 *
 * decision.outcome:
 *   "allowed"        -> نفّذ الإلغاء
 *   "already_closed" -> الرحلة منتهية (cancelled/completed/expired) → idempotent/no-op
 *   "locked"         -> بعد التوجه؛ ارفض بـ TAXI_CANCELLATION_LOCKED
 *   "not_permitted"  -> الطرف لا يملك الإلغاء في هذه الحالة (مثلاً الكابتن قبل الإسناد)
 */
export function evaluateTaxiCancellation({ status, actorRole } = {}) {
  const s = normalizeStatus(status);
  const role = normalizeStatus(actorRole);

  if (TAXI_TERMINAL_STATUSES.includes(s)) {
    return { outcome: "already_closed", status: s };
  }

  if (TAXI_CANCELLATION_LOCKED_STATUSES.includes(s)) {
    return { outcome: "locked", code: "TAXI_CANCELLATION_LOCKED", status: s };
  }

  const cancellable =
    role === "captain"
      ? TAXI_CAPTAIN_CANCELLABLE_STATUSES
      : TAXI_CUSTOMER_CANCELLABLE_STATUSES;

  if (cancellable.includes(s)) {
    return { outcome: "allowed", status: s };
  }

  return {
    outcome: "not_permitted",
    code: "TAXI_CANCELLATION_LOCKED",
    status: s,
  };
}
