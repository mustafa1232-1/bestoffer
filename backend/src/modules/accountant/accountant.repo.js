import { pool, q } from "../../config/db.js";

function toNum(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

export async function getAccountantMerchant(accountantUserId) {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.owner_user_id
     FROM merchant_accountant ma
     JOIN merchant m ON m.id = ma.merchant_id
     WHERE ma.accountant_user_id = $1
       AND ma.is_active = TRUE
       AND m.is_disabled = FALSE
     ORDER BY ma.updated_at DESC, ma.created_at DESC
     LIMIT 1`,
    [Number(accountantUserId)]
  );
  return r.rows[0] || null;
}

export async function getOwnerMerchant(ownerUserId) {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.owner_user_id
     FROM merchant m
     WHERE m.owner_user_id = $1
       AND m.is_disabled = FALSE
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function listMerchantHrUsers(merchantId) {
  const r = await q(
    `SELECT DISTINCT u.id
     FROM merchant_hr_staff hs
     JOIN app_user u ON u.id = hs.hr_user_id
     WHERE hs.merchant_id = $1
       AND hs.is_active = TRUE
       AND u.is_account_disabled = FALSE`,
    [Number(merchantId)]
  );
  return r.rows.map((row) => Number(row.id || 0)).filter((id) => id > 0);
}

export async function listPendingDeliverySettlements(merchantId, limit = 100) {
  const safeLimit = Math.max(1, Math.min(300, Number(limit) || 100));
  const r = await q(
    `SELECT
       s.id,
       s.merchant_id,
       s.delivery_user_id,
       s.archive_date,
       s.orders_count,
       s.total_amount,
       s.status,
       s.requested_at,
       s.received_at,
       s.note,
       u.full_name AS delivery_full_name,
       u.phone AS delivery_phone
     FROM delivery_cash_settlement s
     JOIN app_user u ON u.id = s.delivery_user_id
     WHERE s.merchant_id = $1
       AND s.status = 'pending'
     ORDER BY s.requested_at ASC, s.id ASC
     LIMIT $2`,
    [Number(merchantId), safeLimit]
  );
  return r.rows;
}

async function cashSummaryWithClient(client, merchantId) {
  const cash = await client.query(
    `SELECT
       COALESCE(
         SUM(
           CASE
             WHEN direction = 'credit' THEN amount
             WHEN direction = 'debit' THEN -amount
             ELSE 0
           END
         ),
         0
       ) AS balance,
       COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0) AS total_credit,
       COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0) AS total_debit
     FROM merchant_cash_ledger_entry
     WHERE merchant_id = $1`,
    [Number(merchantId)]
  );

  const pending = await client.query(
    `SELECT
       COALESCE(SUM(total_amount), 0) AS pending_amount,
       COUNT(*)::int AS pending_count
     FROM delivery_cash_settlement
     WHERE merchant_id = $1
       AND status = 'pending'`,
    [Number(merchantId)]
  );

  return {
    balance: toNum(cash.rows[0]?.balance),
    totalCredit: toNum(cash.rows[0]?.total_credit),
    totalDebit: toNum(cash.rows[0]?.total_debit),
    pendingAmount: toNum(pending.rows[0]?.pending_amount),
    pendingCount: Number(pending.rows[0]?.pending_count || 0),
  };
}

export async function getCashSummary(merchantId) {
  const client = await pool.connect();
  try {
    return await cashSummaryWithClient(client, merchantId);
  } finally {
    client.release();
  }
}

export async function listLedgerEntries(merchantId, limit = 100) {
  const safeLimit = Math.max(1, Math.min(300, Number(limit) || 100));
  const r = await q(
    `SELECT
       e.id,
       e.merchant_id,
       e.entry_type,
       e.direction,
       e.amount,
       e.source_delivery_user_id,
       e.source_settlement_id,
       e.source_archive_date,
       e.note,
       e.created_by_user_id,
       e.created_at,
       creator.full_name AS created_by_full_name,
       d.full_name AS source_delivery_full_name
     FROM merchant_cash_ledger_entry e
     LEFT JOIN app_user creator ON creator.id = e.created_by_user_id
     LEFT JOIN app_user d ON d.id = e.source_delivery_user_id
     WHERE e.merchant_id = $1
     ORDER BY e.created_at DESC, e.id DESC
     LIMIT $2`,
    [Number(merchantId), safeLimit]
  );
  return r.rows;
}

export async function addOpeningBalance({
  merchantId,
  accountantUserId,
  amount,
  note,
}) {
  const r = await q(
    `INSERT INTO merchant_cash_ledger_entry
      (
        merchant_id,
        entry_type,
        direction,
        amount,
        note,
        created_by_user_id,
        created_at
      )
     VALUES ($1,'opening_balance','credit',$2,$3,$4,NOW())
     RETURNING *`,
    [
      Number(merchantId),
      toNum(amount),
      note ? String(note).slice(0, 1000) : null,
      Number(accountantUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function addExpense({
  merchantId,
  accountantUserId,
  amount,
  note,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const summary = await cashSummaryWithClient(client, merchantId);
    const numericAmount = toNum(amount);
    if (summary.balance < numericAmount) {
      const err = new Error("INSUFFICIENT_CASH_BALANCE");
      err.status = 409;
      err.details = {
        balance: summary.balance,
        requiredAmount: numericAmount,
      };
      throw err;
    }

    const inserted = await client.query(
      `INSERT INTO merchant_cash_ledger_entry
        (
          merchant_id,
          entry_type,
          direction,
          amount,
          note,
          created_by_user_id,
          created_at
        )
       VALUES ($1,'expense','debit',$2,$3,$4,NOW())
       RETURNING *`,
      [
        Number(merchantId),
        numericAmount,
        note ? String(note).slice(0, 1000) : null,
        Number(accountantUserId),
      ]
    );

    const nextSummary = await cashSummaryWithClient(client, merchantId);
    await client.query("COMMIT");
    return {
      entry: inserted.rows[0] || null,
      summary: nextSummary,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function confirmDeliverySettlementReceipt({
  merchantId,
  accountantUserId,
  settlementId,
  note,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const found = await client.query(
      `SELECT
         s.id,
         s.merchant_id,
         s.delivery_user_id,
         s.archive_date,
         s.orders_count,
         s.total_amount,
         s.status,
         s.requested_at,
         u.full_name AS delivery_full_name,
         u.phone AS delivery_phone
       FROM delivery_cash_settlement s
       JOIN app_user u ON u.id = s.delivery_user_id
       WHERE s.id = $1
         AND s.merchant_id = $2
         AND s.status = 'pending'
       FOR UPDATE`,
      [Number(settlementId), Number(merchantId)]
    );
    const row = found.rows[0];
    if (!row) return null;

    const updated = await client.query(
      `UPDATE delivery_cash_settlement
       SET status = 'received',
           received_by_user_id = $2,
           received_at = NOW(),
           note = COALESCE($3, note),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(settlementId),
        Number(accountantUserId),
        note ? String(note).slice(0, 1000) : null,
      ]
    );

    await client.query(
      `INSERT INTO merchant_cash_ledger_entry
        (
          merchant_id,
          entry_type,
          direction,
          amount,
          source_delivery_user_id,
          source_settlement_id,
          source_archive_date,
          note,
          created_by_user_id,
          created_at
        )
       VALUES ($1,'delivery_settlement','credit',$2,$3,$4,$5,$6,$7,NOW())`,
      [
        Number(merchantId),
        toNum(row.total_amount),
        Number(row.delivery_user_id),
        Number(row.id),
        row.archive_date,
        note ? String(note).slice(0, 1000) : null,
        Number(accountantUserId),
      ]
    );

    const summary = await cashSummaryWithClient(client, merchantId);

    await client.query("COMMIT");
    return {
      settlement: updated.rows[0] || row,
      summary,
      deliveryUserId: Number(row.delivery_user_id),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listPendingPayrollBatches(merchantId, limit = 60) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 60));
  const r = await q(
    `SELECT
       pb.*,
       COALESCE(COUNT(pi.id), 0)::int AS employees_count,
       COALESCE(SUM(pi.net_salary), 0) AS total_net_salary,
       COALESCE(SUM(CASE WHEN pi.status = 'paid' THEN pi.net_salary ELSE 0 END), 0) AS total_paid_salary,
       COALESCE(SUM(CASE WHEN pi.status = 'pending' THEN pi.net_salary ELSE 0 END), 0) AS total_pending_salary
     FROM merchant_payroll_batch pb
     LEFT JOIN merchant_payroll_item pi ON pi.batch_id = pb.id
     WHERE pb.merchant_id = $1
       AND pb.status IN ('submitted', 'processing')
     GROUP BY pb.id
     ORDER BY pb.period_year DESC, pb.period_month DESC, pb.id DESC
     LIMIT $2`,
    [Number(merchantId), safeLimit]
  );
  return r.rows;
}

export async function getPayrollBatchById(merchantId, batchId) {
  const r = await q(
    `SELECT *
     FROM merchant_payroll_batch
     WHERE id = $1
       AND merchant_id = $2
     LIMIT 1`,
    [Number(batchId), Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listPayrollItemsByBatch(batchId) {
  const r = await q(
    `SELECT
       pi.*,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone,
       u.image_url AS employee_image_url
     FROM merchant_payroll_item pi
     JOIN app_user u ON u.id = pi.employee_user_id
     WHERE pi.batch_id = $1
     ORDER BY u.full_name ASC, pi.employee_user_id ASC`,
    [Number(batchId)]
  );
  return r.rows;
}

export async function acknowledgePayrollBatch({
  merchantId,
  batchId,
  accountantUserId,
}) {
  const r = await q(
    `UPDATE merchant_payroll_batch
     SET
       status = CASE WHEN status = 'submitted' THEN 'processing' ELSE status END,
       acknowledged_by_user_id = $3,
       acknowledged_at = NOW(),
       updated_at = NOW()
     WHERE id = $1
       AND merchant_id = $2
       AND status IN ('submitted', 'processing')
     RETURNING *`,
    [Number(batchId), Number(merchantId), Number(accountantUserId)]
  );
  return r.rows[0] || null;
}

export async function markPayrollItemPaid({
  merchantId,
  itemId,
  accountantUserId,
  payoutNote,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const found = await client.query(
      `SELECT
         pi.*,
         pb.status AS batch_status,
         pb.id AS batch_id
       FROM merchant_payroll_item pi
       JOIN merchant_payroll_batch pb ON pb.id = pi.batch_id
       WHERE pi.id = $1
         AND pi.merchant_id = $2
       FOR UPDATE`,
      [Number(itemId), Number(merchantId)]
    );
    const row = found.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return null;
    }
    if (["closed", "cancelled"].includes(String(row.batch_status || ""))) {
      const err = new Error("PAYROLL_BATCH_CLOSED");
      err.status = 409;
      throw err;
    }

    const updated = await client.query(
      `UPDATE merchant_payroll_item
       SET
         status = 'paid',
         paid_by_user_id = $2,
         paid_at = NOW(),
         payout_note = COALESCE($3, payout_note),
         updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(itemId),
        Number(accountantUserId),
        payoutNote ? String(payoutNote).slice(0, 3000) : null,
      ]
    );

    await client.query(
      `UPDATE merchant_payroll_batch
       SET updated_at = NOW()
       WHERE id = $1`,
      [Number(row.batch_id)]
    );

    await client.query("COMMIT");
    return {
      item: updated.rows[0] || row,
      batchId: Number(row.batch_id),
      employeeUserId: Number(row.employee_user_id),
      netSalary: Number(row.net_salary || 0),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
