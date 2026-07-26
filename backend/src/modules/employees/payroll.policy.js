/**
 * Purpose:
 * سياسة دورة الرواتب النقية (المرحلة 7). حالات + انتقالات + حساب الصافي.
 * بلا وصول لقاعدة البيانات — قابلة للاختبار وحدةً.
 */

export const PAYROLL_STATUSES = Object.freeze([
  "DRAFT", "CALCULATED", "UNDER_REVIEW", "APPROVED", "RELEASED",
  "PAID", "ACKNOWLEDGED", "ARCHIVED",
]);

// بعد الأرشفة لا تعديل؛ أي تصحيح يكون Adjustment مستقل.
export const PAYROLL_TERMINAL_STATUSES = Object.freeze(["ARCHIVED"]);

export const PAYROLL_TRANSITIONS = Object.freeze({
  DRAFT: ["CALCULATED"],
  CALCULATED: ["UNDER_REVIEW", "DRAFT"],       // يُعاد للمسودة لإعادة الحساب
  UNDER_REVIEW: ["APPROVED", "CALCULATED"],    // يُعاد إن رُفضت المراجعة
  APPROVED: ["RELEASED"],
  RELEASED: ["PAID"],
  PAID: ["ACKNOWLEDGED"],
  ACKNOWLEDGED: ["ARCHIVED"],
  ARCHIVED: [],
});

// الحالات التي يُسمح فيها بإعادة الحساب (تعديل البنود).
export const PAYROLL_RECALCULABLE = Object.freeze(["DRAFT", "CALCULATED"]);

export function isValidPayrollStatus(s) {
  return PAYROLL_STATUSES.includes(String(s || ""));
}

export function isPayrollTerminal(s) {
  return PAYROLL_TERMINAL_STATUSES.includes(String(s || ""));
}

export function canPayrollTransition(from, to) {
  const next = PAYROLL_TRANSITIONS[String(from || "")];
  return Array.isArray(next) && next.includes(String(to || ""));
}

export function canRecalculate(status) {
  return PAYROLL_RECALCULABLE.includes(String(status || ""));
}

/**
 * صافي الراتب = الأساسي + الإضافات − الخصومات (لا يقل عن صفر).
 */
export function computeNet({ baseSalaryIqd = 0, additionsIqd = 0, deductionsIqd = 0 }) {
  const base = Math.max(0, Math.round(Number(baseSalaryIqd) || 0));
  const add = Math.max(0, Math.round(Number(additionsIqd) || 0));
  const ded = Math.max(0, Math.round(Number(deductionsIqd) || 0));
  return Math.max(0, base + add - ded);
}
