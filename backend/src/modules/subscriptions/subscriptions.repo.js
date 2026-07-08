import { pool, q } from "../../config/db.js";
import { insertOpsAuditLog } from "../../ops/auditLog.js";
import {
  applySubscriptionPayment,
  buildInvoiceDraft,
  resolveBillingMonth,
  resolveWaive,
  roundMoney,
  selectMerchantsNeedingInvoice,
} from "./subscriptions.logic.js";

/**
 * Data-access layer for the merchant monthly subscription debt lifecycle.
 * Ops audit rows are written inside the same transaction as the mutation so an
 * invoice/payment can never exist without its audit trail. Notifications are
 * emitted by the service AFTER commit.
 */

const INVOICE_COLUMNS = `
  id, merchant_id, billing_month, subscription_amount, paid_amount,
  remaining_amount, status, billing_profile_snapshot_json, generated_at,
  due_at, paid_at, notes, created_by_user_id, updated_by_user_id,
  created_at, updated_at
`;

/**
 * All active merchants billed by monthly subscription with amount > 0.
 */
export async function listSubscriptionMerchantCandidates(client = null) {
  const db = client && typeof client.query === "function" ? client : { query: q };
  const result = await db.query(
    `SELECT
       m.id AS merchant_id,
       m.name AS merchant_name,
       bp.commission_model,
       bp.monthly_subscription_amount,
       bp.profile_version,
       bp.service_fee_value
     FROM merchant m
     JOIN merchant_billing_profile bp ON bp.merchant_id = m.id
     WHERE COALESCE(m.is_disabled, FALSE) = FALSE
       AND bp.commission_model = 'monthly_subscription'
       AND COALESCE(bp.monthly_subscription_amount, 0) > 0
     ORDER BY m.name ASC, m.id ASC`
  );
  return result.rows.map((row) => ({
    merchantId: Number(row.merchant_id),
    merchantName: row.merchant_name,
    commissionModel: row.commission_model,
    monthlySubscriptionAmount: Number(row.monthly_subscription_amount || 0),
    profileVersion: Number(row.profile_version || 1),
    serviceFeeValue: Number(row.service_fee_value || 0),
  }));
}

export async function listExistingInvoiceMerchantIdsForMonth(billingMonth, client = null) {
  const db = client && typeof client.query === "function" ? client : { query: q };
  const month = resolveBillingMonth(billingMonth);
  const result = await db.query(
    `SELECT merchant_id
       FROM merchant_monthly_subscription_invoice
      WHERE billing_month = $1::date`,
    [month]
  );
  return result.rows.map((row) => Number(row.merchant_id));
}

/**
 * Generates one pending invoice per subscription merchant for the given month.
 * Idempotent: relies on selectMerchantsNeedingInvoice (skips existing) AND the
 * unique (merchant_id, billing_month) index via ON CONFLICT DO NOTHING.
 */
export async function generateInvoices({ billingMonth, actorUserId = null } = {}) {
  const month = resolveBillingMonth(billingMonth);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const candidates = await listSubscriptionMerchantCandidates(client);
    const existing = await listExistingInvoiceMerchantIdsForMonth(month, client);
    const needing = selectMerchantsNeedingInvoice(candidates, existing, month);

    const inserted = [];
    for (const item of needing) {
      const draft = buildInvoiceDraft({
        merchantId: item.merchantId,
        profile: item.profile,
        billingMonth: month,
        actorUserId,
      });
      const res = await client.query(
        `INSERT INTO merchant_monthly_subscription_invoice
           (merchant_id, billing_month, subscription_amount, paid_amount,
            remaining_amount, status, billing_profile_snapshot_json,
            due_at, notes, created_by_user_id, updated_by_user_id)
         VALUES ($1,$2::date,$3,0,$4,'pending',$5::jsonb,$6::timestamptz,NULL,$7,$7)
         ON CONFLICT (merchant_id, billing_month) DO NOTHING
         RETURNING ${INVOICE_COLUMNS}`,
        [
          draft.merchantId,
          draft.billingMonth,
          draft.subscriptionAmount,
          draft.remainingAmount,
          JSON.stringify(draft.billingProfileSnapshot),
          draft.dueAt,
          actorUserId == null ? null : Number(actorUserId),
        ]
      );
      const row = res.rows[0];
      if (!row) continue; // lost the ON CONFLICT race — already generated

      await insertOpsAuditLog({
        actorUserId: actorUserId == null ? null : Number(actorUserId),
        actorRole: "admin",
        action: "merchant_monthly_subscription_invoice_generated",
        targetType: "merchant_monthly_subscription_invoice",
        targetId: Number(row.id),
        metadata: {
          merchantId: draft.merchantId,
          billingMonth: month,
          subscriptionAmount: draft.subscriptionAmount,
        },
        client,
      });
      inserted.push({ ...row, merchant_name: item.merchantName });
    }

    await client.query("COMMIT");
    return {
      billingMonth: month,
      generatedCount: inserted.length,
      candidateCount: candidates.length,
      skippedExistingCount: candidates.length - needing.length,
      invoices: inserted,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listInvoices({ status = null, billingMonth = null, merchantId = null, limit = 200 } = {}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 200));
  const conditions = [];
  const params = [];
  if (status) {
    params.push(String(status).trim().toLowerCase());
    conditions.push(`i.status = $${params.length}`);
  }
  if (billingMonth) {
    params.push(resolveBillingMonth(billingMonth));
    conditions.push(`i.billing_month = $${params.length}::date`);
  }
  if (merchantId) {
    params.push(Number(merchantId));
    conditions.push(`i.merchant_id = $${params.length}`);
  }
  params.push(safeLimit);
  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
  const result = await q(
    `SELECT
       i.id, i.merchant_id, i.billing_month, i.subscription_amount,
       i.paid_amount, i.remaining_amount, i.status, i.generated_at,
       i.due_at, i.paid_at, i.notes, i.created_at, i.updated_at,
       m.name AS merchant_name,
       COALESCE(m.owner_user_id, NULL) AS owner_user_id
     FROM merchant_monthly_subscription_invoice i
     JOIN merchant m ON m.id = i.merchant_id
     ${where}
     ORDER BY i.billing_month DESC, m.name ASC, i.id DESC
     LIMIT $${params.length}`,
    params
  );
  return result.rows;
}

export async function getInvoiceById(invoiceId) {
  const result = await q(
    `SELECT
       i.id, i.merchant_id, i.billing_month, i.subscription_amount,
       i.paid_amount, i.remaining_amount, i.status, i.generated_at,
       i.due_at, i.paid_at, i.notes, i.created_at, i.updated_at,
       m.name AS merchant_name,
       m.owner_user_id
     FROM merchant_monthly_subscription_invoice i
     JOIN merchant m ON m.id = i.merchant_id
     WHERE i.id = $1
     LIMIT 1`,
    [Number(invoiceId)]
  );
  return result.rows[0] || null;
}

export async function listInvoicePayments(invoiceId, limit = 100) {
  const safeLimit = Math.max(1, Math.min(300, Number(limit) || 100));
  const result = await q(
    `SELECT
       p.id, p.invoice_id, p.merchant_id, p.amount, p.payment_method,
       p.received_by_user_id, p.notes, p.created_at,
       u.full_name AS received_by_full_name
     FROM merchant_monthly_subscription_payment p
     LEFT JOIN app_user u ON u.id = p.received_by_user_id
     WHERE p.invoice_id = $1
     ORDER BY p.created_at DESC, p.id DESC
     LIMIT $2`,
    [Number(invoiceId), safeLimit]
  );
  return result.rows;
}

/**
 * Records a payment against an invoice. Exact payment -> paid; partial ->
 * partially_paid with the remaining balance kept. Overpayment is clamped.
 * Money math is delegated to the pure applySubscriptionPayment.
 */
export async function recordPayment({
  invoiceId,
  amount,
  paymentMethod = "cash",
  actorUserId = null,
  actorRole = "admin",
  notes = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const found = await client.query(
      `SELECT ${INVOICE_COLUMNS}, (SELECT owner_user_id FROM merchant WHERE id = merchant_id) AS owner_user_id
       FROM merchant_monthly_subscription_invoice
       WHERE id = $1
       FOR UPDATE`,
      [Number(invoiceId)]
    );
    const invoice = found.rows[0];
    if (!invoice) {
      await client.query("ROLLBACK");
      return null;
    }

    const applied = applySubscriptionPayment({ invoice, amount });

    const trimmedNotes = notes ? String(notes).slice(0, 1000) : null;
    await client.query(
      `INSERT INTO merchant_monthly_subscription_payment
         (invoice_id, merchant_id, amount, payment_method, received_by_user_id, notes)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [
        Number(invoiceId),
        Number(invoice.merchant_id),
        applied.appliedAmount,
        String(paymentMethod || "cash").slice(0, 30),
        actorUserId == null ? null : Number(actorUserId),
        trimmedNotes,
      ]
    );

    const updated = await client.query(
      `UPDATE merchant_monthly_subscription_invoice
       SET paid_amount = $2,
           remaining_amount = $3,
           status = $4,
           paid_at = CASE WHEN $4 = 'paid' THEN COALESCE(paid_at, NOW()) ELSE paid_at END,
           notes = COALESCE($5, notes),
           updated_by_user_id = $6,
           updated_at = NOW()
       WHERE id = $1
       RETURNING ${INVOICE_COLUMNS}`,
      [
        Number(invoiceId),
        applied.paidAmount,
        applied.remainingAmount,
        applied.status,
        trimmedNotes,
        actorUserId == null ? null : Number(actorUserId),
      ]
    );

    await insertOpsAuditLog({
      actorUserId: actorUserId == null ? null : Number(actorUserId),
      actorRole,
      action:
        applied.status === "paid"
          ? "merchant_monthly_subscription_payment_received"
          : "merchant_monthly_subscription_partial_payment",
      targetType: "merchant_monthly_subscription_invoice",
      targetId: Number(invoiceId),
      metadata: {
        merchantId: Number(invoice.merchant_id),
        appliedAmount: applied.appliedAmount,
        overpaymentIgnored: applied.overpaymentIgnored,
        paidAmount: applied.paidAmount,
        remainingAmount: applied.remainingAmount,
        status: applied.status,
        paymentMethod: String(paymentMethod || "cash"),
      },
      client,
    });

    await client.query("COMMIT");
    return {
      invoice: updated.rows[0] || invoice,
      applied,
      ownerUserId: invoice.owner_user_id ? Number(invoice.owner_user_id) : null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Explicitly waives an invoice. Reason is required (enforced by resolveWaive).
 */
export async function waiveInvoice({ invoiceId, reason, actorUserId = null, actorRole = "admin" }) {
  const normalizedReason = resolveWaive({ reason });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const found = await client.query(
      `SELECT ${INVOICE_COLUMNS}, (SELECT owner_user_id FROM merchant WHERE id = merchant_id) AS owner_user_id
       FROM merchant_monthly_subscription_invoice
       WHERE id = $1
       FOR UPDATE`,
      [Number(invoiceId)]
    );
    const invoice = found.rows[0];
    if (!invoice) {
      await client.query("ROLLBACK");
      return null;
    }
    if (String(invoice.status) === "paid") {
      const err = new Error("SUBSCRIPTION_INVOICE_ALREADY_PAID");
      err.status = 409;
      throw err;
    }

    const updated = await client.query(
      `UPDATE merchant_monthly_subscription_invoice
       SET status = 'waived',
           remaining_amount = 0,
           notes = $2,
           updated_by_user_id = $3,
           updated_at = NOW()
       WHERE id = $1
       RETURNING ${INVOICE_COLUMNS}`,
      [Number(invoiceId), normalizedReason, actorUserId == null ? null : Number(actorUserId)]
    );

    await insertOpsAuditLog({
      actorUserId: actorUserId == null ? null : Number(actorUserId),
      actorRole,
      action: "merchant_monthly_subscription_invoice_waived",
      targetType: "merchant_monthly_subscription_invoice",
      targetId: Number(invoiceId),
      metadata: {
        merchantId: Number(invoice.merchant_id),
        subscriptionAmount: roundMoney(invoice.subscription_amount),
        reason: normalizedReason,
      },
      client,
    });

    await client.query("COMMIT");
    return {
      invoice: updated.rows[0] || invoice,
      ownerUserId: invoice.owner_user_id ? Number(invoice.owner_user_id) : null,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Owner-facing view: the merchant's own invoices (most recent first) plus a
 * separated debt summary. Scoped strictly to one merchant id.
 */
export async function getMerchantSubscriptionInvoices(merchantId, limit = 24) {
  const safeLimit = Math.max(1, Math.min(120, Number(limit) || 24));
  const result = await q(
    `SELECT ${INVOICE_COLUMNS}
     FROM merchant_monthly_subscription_invoice
     WHERE merchant_id = $1
     ORDER BY billing_month DESC, id DESC
     LIMIT $2`,
    [Number(merchantId), safeLimit]
  );
  return result.rows;
}

/**
 * Aggregated subscription debt for a merchant — intentionally SEPARATE from any
 * per-order cash settlement figures.
 */
export async function getMerchantSubscriptionReport(merchantId) {
  const result = await q(
    `SELECT
       COALESCE(SUM(subscription_amount), 0) AS total_billed,
       COALESCE(SUM(paid_amount), 0) AS total_paid,
       COALESCE(SUM(
         CASE WHEN status = 'waived' THEN 0 ELSE remaining_amount END
       ), 0) AS total_remaining,
       COALESCE(SUM(CASE WHEN status IN ('pending','partially_paid','overdue') THEN 1 ELSE 0 END), 0)::int AS open_count,
       COALESCE(SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END), 0)::int AS overdue_count,
       COUNT(*)::int AS invoice_count
     FROM merchant_monthly_subscription_invoice
     WHERE merchant_id = $1`,
    [Number(merchantId)]
  );
  const row = result.rows[0] || {};
  return {
    totalBilled: roundMoney(row.total_billed),
    totalPaid: roundMoney(row.total_paid),
    totalRemaining: roundMoney(row.total_remaining),
    openCount: Number(row.open_count || 0),
    overdueCount: Number(row.overdue_count || 0),
    invoiceCount: Number(row.invoice_count || 0),
  };
}
