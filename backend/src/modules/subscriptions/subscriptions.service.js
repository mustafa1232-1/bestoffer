import { createManyNotifications } from "../notifications/notifications.repo.js";
import * as repo from "./subscriptions.repo.js";
import { roundMoney } from "./subscriptions.logic.js";

function mapInvoice(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    merchantName: row.merchant_name || null,
    billingMonth:
      row.billing_month instanceof Date
        ? row.billing_month.toISOString().slice(0, 10)
        : row.billing_month,
    subscriptionAmount: roundMoney(row.subscription_amount),
    paidAmount: roundMoney(row.paid_amount),
    remainingAmount: roundMoney(row.remaining_amount),
    status: row.status,
    generatedAt: row.generated_at || null,
    dueAt: row.due_at || null,
    paidAt: row.paid_at || null,
    notes: row.notes || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapPayment(row) {
  return {
    id: Number(row.id),
    invoiceId: Number(row.invoice_id),
    merchantId: Number(row.merchant_id),
    amount: roundMoney(row.amount),
    paymentMethod: row.payment_method || "cash",
    receivedByUserId: row.received_by_user_id ? Number(row.received_by_user_id) : null,
    receivedByFullName: row.received_by_full_name || null,
    notes: row.notes || null,
    createdAt: row.created_at || null,
  };
}

function fmt(amount) {
  return Number(amount || 0).toFixed(0);
}

export async function generateInvoices({ month = null, actorUserId = null } = {}) {
  const out = await repo.generateInvoices({ billingMonth: month, actorUserId });

  if (out.invoices.length > 0) {
    const notifications = [];
    for (const row of out.invoices) {
      const ownerRes = row.owner_user_id ? Number(row.owner_user_id) : null;
      if (!ownerRes) continue;
      notifications.push({
        userId: ownerRes,
        type: "owner.subscription.invoice_generated",
        title: "فاتورة اشتراك شهري جديدة",
        body: `تم إصدار فاتورة اشتراك شهري بقيمة ${fmt(row.subscription_amount)} د.ع لشهر ${out.billingMonth}.`,
        merchantId: Number(row.merchant_id),
        payload: {
          invoiceId: Number(row.id),
          merchantId: Number(row.merchant_id),
          billingMonth: out.billingMonth,
          subscriptionAmount: roundMoney(row.subscription_amount),
          target: "owner_dashboard",
        },
      });
    }
    if (notifications.length) await createManyNotifications(notifications);
  }

  return {
    billingMonth: out.billingMonth,
    generatedCount: out.generatedCount,
    candidateCount: out.candidateCount,
    skippedExistingCount: out.skippedExistingCount,
    invoices: out.invoices.map(mapInvoice),
  };
}

export async function listInvoices(filters = {}) {
  const rows = await repo.listInvoices(filters);
  return rows.map(mapInvoice);
}

export async function getInvoiceDetail(invoiceId) {
  const invoice = await repo.getInvoiceById(invoiceId);
  if (!invoice) {
    const err = new Error("SUBSCRIPTION_INVOICE_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const payments = await repo.listInvoicePayments(invoiceId);
  return {
    invoice: mapInvoice(invoice),
    payments: payments.map(mapPayment),
  };
}

export async function recordPayment({
  invoiceId,
  amount,
  paymentMethod = "cash",
  notes = null,
  actorUserId = null,
  actorRole = "admin",
}) {
  const out = await repo.recordPayment({
    invoiceId,
    amount,
    paymentMethod,
    notes,
    actorUserId,
    actorRole,
  });
  if (!out) {
    const err = new Error("SUBSCRIPTION_INVOICE_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const invoice = out.invoice;
  const paid = out.status === "paid" || invoice.status === "paid";
  if (out.ownerUserId) {
    await createManyNotifications([
      {
        userId: out.ownerUserId,
        type: "owner.subscription.payment_received",
        title: paid ? "تم سداد الاشتراك الشهري" : "دفعة اشتراك مستلمة",
        body: paid
          ? `تم تأكيد سداد فاتورة الاشتراك بالكامل بقيمة ${fmt(invoice.subscription_amount)} د.ع.`
          : `تم استلام دفعة ${fmt(out.applied.appliedAmount)} د.ع، والمتبقي ${fmt(out.applied.remainingAmount)} د.ع.`,
        merchantId: Number(invoice.merchant_id),
        payload: {
          invoiceId: Number(invoice.id),
          merchantId: Number(invoice.merchant_id),
          amount: roundMoney(out.applied.appliedAmount),
          remainingAmount: roundMoney(out.applied.remainingAmount),
          status: invoice.status,
          target: "owner_dashboard",
        },
      },
    ]);
  }

  return {
    invoice: mapInvoice(invoice),
    applied: out.applied,
  };
}

export async function waiveInvoice({ invoiceId, reason, actorUserId = null, actorRole = "admin" }) {
  const out = await repo.waiveInvoice({ invoiceId, reason, actorUserId, actorRole });
  if (!out) {
    const err = new Error("SUBSCRIPTION_INVOICE_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (out.ownerUserId) {
    await createManyNotifications([
      {
        userId: out.ownerUserId,
        type: "owner.subscription.waived",
        title: "تم إعفاء فاتورة الاشتراك",
        body: `تم إعفاء فاتورة الاشتراك الشهري. السبب: ${out.invoice.notes || "-"}.`,
        merchantId: Number(out.invoice.merchant_id),
        payload: {
          invoiceId: Number(out.invoice.id),
          merchantId: Number(out.invoice.merchant_id),
          status: "waived",
          target: "owner_dashboard",
        },
      },
    ]);
  }
  return { invoice: mapInvoice(out.invoice) };
}

/**
 * Owner-facing summary: current-month invoice, recent invoices, and a debt
 * roll-up. Kept strictly separate from per-order cash settlement figures.
 */
export async function getMerchantSubscriptionSummary(merchantId, { billingModel = null } = {}) {
  const [invoices, report] = await Promise.all([
    repo.getMerchantSubscriptionInvoices(merchantId, 24),
    repo.getMerchantSubscriptionReport(merchantId),
  ]);
  const mapped = invoices.map(mapInvoice);
  return {
    merchantId: Number(merchantId),
    commissionModel: billingModel,
    isMonthlySubscription: billingModel === "monthly_subscription",
    currentInvoice: mapped[0] || null,
    invoices: mapped,
    report,
  };
}
