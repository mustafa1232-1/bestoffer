import { AppError } from "../../shared/utils/errors.js";

/**
 * Pure business rules for the merchant monthly subscription debt/invoice
 * lifecycle. No database access lives here so the rules can be unit tested in
 * isolation (mirrors merchant-financial.logic.js). The invoice debt is fully
 * SEPARATE from per-order cash settlement and never touches commission math.
 */

export const MONTHLY_SUBSCRIPTION_INVOICE_STATUSES = Object.freeze([
  "pending",
  "partially_paid",
  "paid",
  "waived",
  "overdue",
]);

export const SUBSCRIPTION_COMMISSION_MODEL = "monthly_subscription";

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function roundMoney(value) {
  return Math.round((toNumber(value, 0) + Number.EPSILON) * 100) / 100;
}

function pad2(value) {
  return String(value).padStart(2, "0");
}

/**
 * Normalizes any month input to the first day of that month as `YYYY-MM-01`.
 * Accepts a Date, an ISO string, `YYYY-MM`, or nullish (defaults to `now`).
 */
export function resolveBillingMonth(input, now = new Date()) {
  let year;
  let month; // 1-12
  if (input instanceof Date && !Number.isNaN(input.getTime())) {
    year = input.getUTCFullYear();
    month = input.getUTCMonth() + 1;
  } else if (typeof input === "string" && input.trim()) {
    const match = input.trim().match(/^(\d{4})-(\d{1,2})/);
    if (match) {
      year = Number(match[1]);
      month = Number(match[2]);
    }
  }
  if (!year || !month) {
    const base = now instanceof Date && !Number.isNaN(now.getTime()) ? now : new Date();
    year = base.getUTCFullYear();
    month = base.getUTCMonth() + 1;
  }
  if (month < 1) month = 1;
  if (month > 12) month = 12;
  return `${year}-${pad2(month)}-01`;
}

/**
 * Due date for a billing month = first day of the following month (i.e. the
 * subscription for July is due by the end of July). Returned as an ISO string.
 */
export function resolveDueAt(billingMonth, now = new Date()) {
  const month = resolveBillingMonth(billingMonth, now);
  const [year, mon] = month.split("-").map((part) => Number(part));
  const nextYear = mon >= 12 ? year + 1 : year;
  const nextMonth = mon >= 12 ? 1 : mon + 1;
  return `${nextYear}-${pad2(nextMonth)}-01T00:00:00.000Z`;
}

export function normalizeCommissionModel(value) {
  return String(value || "").trim().toLowerCase() === SUBSCRIPTION_COMMISSION_MODEL
    ? SUBSCRIPTION_COMMISSION_MODEL
    : "percentage";
}

export function resolveSubscriptionAmount(profile = {}) {
  const raw =
    profile.monthlySubscriptionAmount ??
    profile.monthly_subscription_amount ??
    0;
  return roundMoney(Math.max(0, toNumber(raw, 0)));
}

/**
 * True only when the merchant is billed by flat monthly subscription AND the
 * amount is > 0. Percentage merchants and zero-amount subscriptions never
 * produce an invoice.
 */
export function shouldGenerateSubscriptionInvoice(profile = {}) {
  const model = normalizeCommissionModel(
    profile.commissionModel ?? profile.commission_model
  );
  if (model !== SUBSCRIPTION_COMMISSION_MODEL) return false;
  return resolveSubscriptionAmount(profile) > 0;
}

/**
 * Derives the lifecycle status from amounts. `waived` is sticky and wins.
 */
export function computeInvoiceStatus({
  subscriptionAmount,
  paidAmount,
  waived = false,
  dueAt = null,
  now = new Date(),
} = {}) {
  if (waived) return "waived";
  const amount = roundMoney(subscriptionAmount);
  const paid = roundMoney(paidAmount);
  if (amount > 0 && paid >= amount - 0.009) return "paid";
  if (paid > 0.009) return "partially_paid";
  if (dueAt) {
    const due = new Date(dueAt);
    const ref = now instanceof Date ? now : new Date(now);
    if (!Number.isNaN(due.getTime()) && ref.getTime() > due.getTime()) {
      return "overdue";
    }
  }
  return "pending";
}

/**
 * Builds the row draft for a brand-new pending invoice. Callers persist this
 * with INSERT ... ON CONFLICT (merchant_id, billing_month) DO NOTHING so the
 * "one invoice per merchant per month" rule is enforced at the DB layer too.
 */
export function buildInvoiceDraft({
  merchantId,
  profile = {},
  billingMonth,
  actorUserId = null,
  now = new Date(),
}) {
  if (!shouldGenerateSubscriptionInvoice(profile)) {
    throw new AppError("SUBSCRIPTION_INVOICE_NOT_APPLICABLE", {
      status: 400,
      details: { merchantId: Number(merchantId) || null },
    });
  }
  const month = resolveBillingMonth(billingMonth, now);
  const subscriptionAmount = resolveSubscriptionAmount(profile);
  return {
    merchantId: Number(merchantId),
    billingMonth: month,
    subscriptionAmount,
    paidAmount: 0,
    remainingAmount: subscriptionAmount,
    status: "pending",
    dueAt: resolveDueAt(month, now),
    createdByUserId: actorUserId == null ? null : Number(actorUserId),
    billingProfileSnapshot: {
      commissionModel: SUBSCRIPTION_COMMISSION_MODEL,
      monthlySubscriptionAmount: subscriptionAmount,
      profileVersion: Number(profile.profileVersion ?? profile.profile_version ?? 1) || 1,
      serviceFeeValue: roundMoney(profile.serviceFeeValue ?? profile.service_fee_value ?? 0),
    },
  };
}

/**
 * Filters a list of merchant candidates down to those that need a new invoice
 * for `billingMonth`: subscription-billed, amount > 0, and no existing invoice
 * for that month. Pure, so generation is provably idempotent and never touches
 * percentage / zero-amount merchants.
 */
export function selectMerchantsNeedingInvoice(
  candidates = [],
  existingMerchantIds = [],
  billingMonth,
  now = new Date()
) {
  const month = resolveBillingMonth(billingMonth, now);
  const already = new Set(
    (Array.isArray(existingMerchantIds) ? existingMerchantIds : []).map((id) =>
      Number(id)
    )
  );
  const seen = new Set();
  const selected = [];
  for (const candidate of Array.isArray(candidates) ? candidates : []) {
    const merchantId = Number(candidate?.merchantId ?? candidate?.merchant_id ?? candidate?.id);
    if (!Number.isInteger(merchantId) || merchantId <= 0) continue;
    if (already.has(merchantId) || seen.has(merchantId)) continue;
    if (!shouldGenerateSubscriptionInvoice(candidate)) continue;
    seen.add(merchantId);
    selected.push({
      merchantId,
      billingMonth: month,
      subscriptionAmount: resolveSubscriptionAmount(candidate),
      profile: candidate,
    });
  }
  return selected;
}

/**
 * Applies a payment to an invoice and returns the next money state. Rejects
 * non-positive amounts and clamps any overpayment to the remaining balance so
 * paid_amount never exceeds subscription_amount.
 */
export function applySubscriptionPayment({ invoice = {}, amount, now = new Date() }) {
  const subscriptionAmount = roundMoney(
    invoice.subscriptionAmount ?? invoice.subscription_amount ?? 0
  );
  const currentPaid = roundMoney(invoice.paidAmount ?? invoice.paid_amount ?? 0);
  const currentStatus = String(invoice.status || "").trim().toLowerCase();
  if (currentStatus === "waived") {
    throw new AppError("SUBSCRIPTION_INVOICE_ALREADY_WAIVED", { status: 409 });
  }
  const requested = roundMoney(amount);
  if (!(requested > 0)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { amount: "PAYMENT_AMOUNT_INVALID" } },
    });
  }
  const remainingBefore = roundMoney(Math.max(0, subscriptionAmount - currentPaid));
  const appliedAmount = roundMoney(Math.min(requested, remainingBefore));
  const paidAmount = roundMoney(currentPaid + appliedAmount);
  const remainingAmount = roundMoney(Math.max(0, subscriptionAmount - paidAmount));
  const status = computeInvoiceStatus({
    subscriptionAmount,
    paidAmount,
    waived: false,
    dueAt: invoice.dueAt ?? invoice.due_at ?? null,
    now,
  });
  const nowIso = now instanceof Date ? now.toISOString() : new Date(now).toISOString();
  return {
    appliedAmount,
    overpaymentIgnored: roundMoney(requested - appliedAmount),
    paidAmount,
    remainingAmount,
    status,
    paidAt: status === "paid" ? nowIso : null,
  };
}

/**
 * Waiving requires an explicit non-empty reason. Returns the normalized reason.
 */
export function resolveWaive({ reason } = {}) {
  const normalized = reason == null ? "" : String(reason).trim();
  if (!normalized) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { reason: "WAIVE_REASON_REQUIRED" } },
    });
  }
  return normalized.slice(0, 1000);
}

export { toNumber };
