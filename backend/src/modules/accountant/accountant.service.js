import { createManyNotifications } from "../notifications/notifications.repo.js";
import * as repo from "./accountant.repo.js";

function resolveActor(actorOrUserId) {
  if (actorOrUserId && typeof actorOrUserId === "object") {
    return {
      userId: Number(actorOrUserId.userId || 0),
      role: String(actorOrUserId.role || "").trim().toLowerCase(),
    };
  }
  return {
    userId: Number(actorOrUserId || 0),
    role: "accountant",
  };
}

function mapSettlement(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    deliveryUserId: Number(row.delivery_user_id),
    deliveryFullName: row.delivery_full_name || "",
    deliveryPhone: row.delivery_phone || "",
    archiveDate: row.archive_date,
    ordersCount: Number(row.orders_count || 0),
    totalAmount: Number(row.total_amount || 0),
    storeNetReceivedAmount: Number(row.store_net_received_amount || 0),
    appDueFromDelivery: Number(row.app_due_from_delivery || 0),
    storeCashConfirmed: row.store_cash_confirmed === true,
    storeCashConfirmedAt: row.store_cash_confirmed_at || null,
    storeCashConfirmedByUserId: row.store_cash_confirmed_by_user_id
      ? Number(row.store_cash_confirmed_by_user_id)
      : null,
    amountReceivedActual: Number(row.amount_received_actual || 0),
    differenceAmount: Number(row.difference_amount || 0),
    differenceReason: row.difference_reason || null,
    settlementStatus: row.settlement_status || "pending_store_confirmation",
    status: row.status,
    requestedAt: row.requested_at,
    receivedAt: row.received_at || null,
    note: row.note || null,
  };
}

function mapLedger(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    entryType: row.entry_type,
    direction: row.direction,
    amount: Number(row.amount || 0),
    sourceDeliveryUserId: row.source_delivery_user_id
      ? Number(row.source_delivery_user_id)
      : null,
    sourceDeliveryFullName: row.source_delivery_full_name || null,
    sourceSettlementId: row.source_settlement_id
      ? Number(row.source_settlement_id)
      : null,
    sourceArchiveDate: row.source_archive_date || null,
    note: row.note || null,
    createdByUserId: row.created_by_user_id ? Number(row.created_by_user_id) : null,
    createdByFullName: row.created_by_full_name || null,
    createdAt: row.created_at,
  };
}

function mapPayrollBatch(row) {
  return {
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    periodYear: Number(row.period_year),
    periodMonth: Number(row.period_month),
    status: row.status,
    summaryNote: row.summary_note || null,
    createdByUserId:
      row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    acknowledgedByUserId:
      row.acknowledged_by_user_id == null
        ? null
        : Number(row.acknowledged_by_user_id),
    acknowledgedAt: row.acknowledged_at || null,
    closedByUserId:
      row.closed_by_user_id == null ? null : Number(row.closed_by_user_id),
    closedAt: row.closed_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    employeesCount:
      row.employees_count == null ? null : Number(row.employees_count),
    totalNetSalary:
      row.total_net_salary == null ? null : Number(row.total_net_salary),
    totalPaidSalary:
      row.total_paid_salary == null ? null : Number(row.total_paid_salary),
    totalPendingSalary:
      row.total_pending_salary == null ? null : Number(row.total_pending_salary),
  };
}

function mapPayrollItem(row) {
  return {
    id: Number(row.id),
    batchId: Number(row.batch_id),
    merchantId: Number(row.merchant_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || "",
    employeePhone: row.employee_phone || "",
    employeeImageUrl: row.employee_image_url || null,
    baseSalary: Number(row.base_salary || 0),
    bonuses: Number(row.bonuses || 0),
    deductions: Number(row.deductions || 0),
    leaveAdjustment: Number(row.leave_adjustment || 0),
    netSalary: Number(row.net_salary || 0),
    status: row.status,
    hrNote: row.hr_note || null,
    payoutNote: row.payout_note || null,
    paidByUserId: row.paid_by_user_id == null ? null : Number(row.paid_by_user_id),
    paidAt: row.paid_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function resolveMerchant(actorOrUserId) {
  const actor = resolveActor(actorOrUserId);
  if (!Number.isInteger(actor.userId) || actor.userId <= 0) {
    const err = new Error("UNAUTHORIZED");
    err.status = 401;
    throw err;
  }

  if (actor.role === "owner") {
    const ownerMerchant = await repo.getOwnerMerchant(actor.userId);
    if (!ownerMerchant) {
      const err = new Error("OWNER_MERCHANT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    return ownerMerchant;
  }

  const accountantMerchant = await repo.getAccountantMerchant(actor.userId);
  if (!accountantMerchant) {
    const err = new Error("ACCOUNTANT_MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return accountantMerchant;
}

export async function getSummary(actorOrUserId) {
  const merchant = await resolveMerchant(actorOrUserId);
  const [summary, pending, ledger] = await Promise.all([
    repo.getCashSummary(merchant.id),
    repo.listPendingDeliverySettlements(merchant.id, 40),
    repo.listLedgerEntries(merchant.id, 40),
  ]);

  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
      type: merchant.type,
      ownerUserId: merchant.owner_user_id ? Number(merchant.owner_user_id) : null,
    },
    summary,
    pendingSettlements: pending.map(mapSettlement),
    ledger: ledger.map(mapLedger),
  };
}

export async function listPendingSettlements(actorOrUserId, { limit = 100 } = {}) {
  const merchant = await resolveMerchant(actorOrUserId);
  const rows = await repo.listPendingDeliverySettlements(merchant.id, limit);
  return rows.map(mapSettlement);
}

export async function listLedger(actorOrUserId, { limit = 100 } = {}) {
  const merchant = await resolveMerchant(actorOrUserId);
  const rows = await repo.listLedgerEntries(merchant.id, limit);
  return rows.map(mapLedger);
}

export async function addOpeningBalance(actorOrUserId, { amount, note }) {
  const actor = resolveActor(actorOrUserId);
  const merchant = await resolveMerchant(actor);
  const numericAmount = Number(amount);
  if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
    const err = new Error("OPENING_BALANCE_INVALID");
    err.status = 400;
    throw err;
  }

  const entry = await repo.addOpeningBalance({
    merchantId: merchant.id,
    accountantUserId: actor.userId,
    amount: numericAmount,
    note,
  });
  const summary = await repo.getCashSummary(merchant.id);

  return {
    entry: mapLedger(entry),
    summary,
  };
}

export async function addExpense(actorOrUserId, { amount, note }) {
  const actor = resolveActor(actorOrUserId);
  const merchant = await resolveMerchant(actor);
  const numericAmount = Number(amount);
  if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
    const err = new Error("EXPENSE_AMOUNT_INVALID");
    err.status = 400;
    throw err;
  }

  const out = await repo.addExpense({
    merchantId: merchant.id,
    accountantUserId: actor.userId,
    amount: numericAmount,
    note,
  });
  return {
    entry: mapLedger(out.entry),
    summary: out.summary,
  };
}

export async function confirmSettlement(
  actorOrUserId,
  settlementId,
  { note, actualAmount = null, differenceReason = null } = {}
) {
  const actor = resolveActor(actorOrUserId);
  const merchant = await resolveMerchant(actor);
  const out = await repo.confirmDeliverySettlementReceipt({
    merchantId: merchant.id,
    accountantUserId: actor.userId,
    settlementId: Number(settlementId),
    note,
    actualAmount,
    differenceReason,
  });
  if (!out) {
    const err = new Error("DELIVERY_SETTLEMENT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const expectedAmount = Number(
    out.settlement.store_net_received_amount ?? out.settlement.total_amount ?? 0
  );
  const actualAmountValue = Number(
    out.settlement.amount_received_actual ?? expectedAmount
  );
  const differenceAmount = Number(out.settlement.difference_amount || 0);
  const differenceReasonValue = out.settlement.difference_reason || null;
  const ownerNotificationBody =
    differenceAmount === 0
      ? `تم تأكيد استلام ذمة الدلفري بقيمة ${expectedAmount.toFixed(0)} د.ع.`
      : `تم تأكيد الاستلام بقيمة ${actualAmountValue.toFixed(
          0
        )} د.ع. ويوجد فرق ${differenceAmount.toFixed(0)} د.ع.`;

  await createManyNotifications(
    [
      merchant.owner_user_id
        ? {
            userId: Number(merchant.owner_user_id),
            type: "owner_delivery_cash_received",
            title: "تم تأكيد استلام ذمة الدلفري",
            body: ownerNotificationBody,
            payload: {
              settlementId: Number(out.settlement.id),
              deliveryUserId: out.deliveryUserId,
              amount: actualAmountValue,
              expectedAmount,
              differenceAmount,
              differenceReason: differenceReasonValue,
              appDueFromDelivery: Number(out.settlement.app_due_from_delivery || 0),
              settlementStatus: out.settlement.settlement_status || "received",
              target: "owner_dashboard",
            },
          }
        : null,
      {
        userId: out.deliveryUserId,
        type: "delivery_cash_settlement_received",
        title: "تم استلام ذمتك اليومية",
        body:
          differenceAmount === 0
            ? `تم تأكيد استلام ذمتك اليومية بتاريخ ${out.settlement.archive_date}.`
            : `تم تأكيد استلام ذمتك اليومية بتاريخ ${out.settlement.archive_date} مع وجود فرق ${differenceAmount.toFixed(0)} د.ع.`,
        payload: {
          settlementId: Number(out.settlement.id),
          merchantId: Number(merchant.id),
          amount: actualAmountValue,
          expectedAmount,
          differenceAmount,
          differenceReason: differenceReasonValue,
          target: "delivery_dashboard",
        },
      },
    ].filter(Boolean)
  );

  return {
    settlement: mapSettlement(out.settlement),
    summary: out.summary,
  };
}

export async function listPendingPayrollBatches(
  actorOrUserId,
  { limit = 60 } = {}
) {
  const merchant = await resolveMerchant(actorOrUserId);
  const rows = await repo.listPendingPayrollBatches(merchant.id, limit);
  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
      type: merchant.type,
      ownerUserId: merchant.owner_user_id ? Number(merchant.owner_user_id) : null,
    },
    items: rows.map(mapPayrollBatch),
  };
}

export async function getPayrollBatch(actorOrUserId, batchId) {
  const merchant = await resolveMerchant(actorOrUserId);
  const batch = await repo.getPayrollBatchById(merchant.id, Number(batchId));
  if (!batch) {
    const err = new Error("PAYROLL_BATCH_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const items = await repo.listPayrollItemsByBatch(batch.id);
  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
      type: merchant.type,
      ownerUserId: merchant.owner_user_id ? Number(merchant.owner_user_id) : null,
    },
    batch: mapPayrollBatch(batch),
    items: items.map(mapPayrollItem),
  };
}

export async function acknowledgePayrollBatch(actorOrUserId, batchId) {
  const actor = resolveActor(actorOrUserId);
  const merchant = await resolveMerchant(actor);
  const updated = await repo.acknowledgePayrollBatch({
    merchantId: merchant.id,
    batchId: Number(batchId),
    accountantUserId: actor.userId,
  });
  if (!updated) {
    const err = new Error("PAYROLL_BATCH_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const hrUsers = await repo.listMerchantHrUsers(merchant.id);
  if (hrUsers.length > 0) {
    await createManyNotifications(
      [...new Set(hrUsers)].map((userId) => ({
        userId,
        type: "hr.payroll.acknowledged",
        title: "Payroll acknowledged",
        body: `Accountant acknowledged payroll batch #${Number(updated.id)}.`,
        payload: {
          target: "hr_dashboard",
          payrollBatchId: Number(updated.id),
          merchantId: Number(merchant.id),
        },
      }))
    );
  }

  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
      type: merchant.type,
      ownerUserId: merchant.owner_user_id ? Number(merchant.owner_user_id) : null,
    },
    batch: mapPayrollBatch(updated),
  };
}

export async function markPayrollItemPaid(actorOrUserId, itemId, { payoutNote }) {
  const actor = resolveActor(actorOrUserId);
  const merchant = await resolveMerchant(actor);
  const out = await repo.markPayrollItemPaid({
    merchantId: merchant.id,
    itemId: Number(itemId),
    accountantUserId: actor.userId,
    payoutNote: payoutNote || null,
  });
  if (!out) {
    const err = new Error("PAYROLL_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  await createManyNotifications(
    [
      Number(out.employeeUserId) > 0
        ? {
            userId: Number(out.employeeUserId),
            type: "employee.payroll.paid",
            title: "Salary delivered",
            body: `Your salary payment of ${Number(out.netSalary || 0).toFixed(0)} IQD was marked as paid.`,
            payload: {
              target: "notifications",
              payrollItemId: Number(out.item.id || itemId),
              payrollBatchId: Number(out.batchId || 0),
              merchantId: Number(merchant.id),
            },
          }
        : null,
      merchant.owner_user_id
        ? {
            userId: Number(merchant.owner_user_id),
            type: "owner.payroll.item_paid",
            title: "Payroll item paid",
            body: `A payroll item was paid for merchant ${merchant.name}.`,
            payload: {
              target: "owner_dashboard",
              payrollItemId: Number(out.item.id || itemId),
              payrollBatchId: Number(out.batchId || 0),
              merchantId: Number(merchant.id),
            },
          }
        : null,
    ].filter(Boolean)
  );

  return {
    merchant: {
      id: Number(merchant.id),
      name: merchant.name,
      type: merchant.type,
      ownerUserId: merchant.owner_user_id ? Number(merchant.owner_user_id) : null,
    },
    item: mapPayrollItem({
      ...out.item,
      employee_full_name: "",
      employee_phone: "",
      employee_image_url: null,
    }),
    batchId: Number(out.batchId),
  };
}
