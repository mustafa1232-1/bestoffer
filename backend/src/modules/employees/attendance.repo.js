/**
 * Purpose:
 * حضور موظفي الشركة (المرحلة 7). التوقيت من الخادم؛ جلسة مفتوحة واحدة فقط
 * (يُفرض بفهرس فريد جزئي)، ولا خروج بلا حضور.
 */

import { q } from "../../config/db.js";

export async function currentOpenSession(employeeUserId) {
  const r = await q(
    `SELECT * FROM company_attendance
     WHERE employee_user_id = $1 AND check_out_at IS NULL
     ORDER BY check_in_at DESC LIMIT 1`,
    [Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function checkIn({ employeeUserId, note = null }) {
  try {
    const r = await q(
      `INSERT INTO company_attendance (employee_user_id, note, source)
       VALUES ($1, $2, 'self')
       RETURNING *`,
      [Number(employeeUserId), note]
    );
    return { code: "OK", attendance: r.rows[0] };
  } catch (error) {
    if (error?.code === "23505") {
      return { code: "ALREADY_CHECKED_IN" };
    }
    throw error;
  }
}

export async function checkOut({ employeeUserId, note = null }) {
  const r = await q(
    `UPDATE company_attendance
     SET check_out_at = NOW(),
         note = COALESCE($2, note),
         updated_at = NOW()
     WHERE employee_user_id = $1 AND check_out_at IS NULL
     RETURNING *`,
    [Number(employeeUserId), note]
  );
  if (!r.rows[0]) return { code: "NOT_CHECKED_IN" };
  return { code: "OK", attendance: r.rows[0] };
}

export async function listForEmployee({ employeeUserId, limit = 30, offset = 0 }) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 30));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const r = await q(
    `SELECT * FROM company_attendance
     WHERE employee_user_id = $1
     ORDER BY check_in_at DESC
     LIMIT $2 OFFSET $3`,
    [Number(employeeUserId), safeLimit, safeOffset]
  );
  return r.rows;
}

export async function adminList({ employeeUserId = null, limit = 50, offset = 0 }) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const params = [];
  let where = "";
  if (employeeUserId) {
    params.push(Number(employeeUserId));
    where = `WHERE a.employee_user_id = $${params.length}`;
  }
  params.push(safeLimit);
  params.push(safeOffset);
  const r = await q(
    `SELECT a.*, u.full_name
     FROM company_attendance a JOIN app_user u ON u.id = a.employee_user_id
     ${where}
     ORDER BY a.check_in_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return r.rows;
}

/**
 * تصحيح إداري لسجل حضور (يُسجَّل من نفّذه وسببه؛ لا يعدّل الموظف سجله النهائي).
 */
export async function adminCorrect({
  attendanceId,
  checkInAt = null,
  checkOutAt = null,
  reason,
  correctedByUserId,
}) {
  const r = await q(
    `UPDATE company_attendance
     SET check_in_at = COALESCE($2, check_in_at),
         check_out_at = COALESCE($3, check_out_at),
         correction_reason = $4,
         corrected_by_user_id = $5,
         source = 'correction',
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(attendanceId), checkInAt, checkOutAt, reason,
      correctedByUserId ? Number(correctedByUserId) : null,
    ]
  );
  if (!r.rows[0]) return { code: "NOT_FOUND" };
  return { code: "OK", attendance: r.rows[0] };
}

// ---------- المصاريف/الإضافات ----------

export async function submitExpense({
  employeeUserId, category, amountIqd, expenseDate = null, reason = null, receiptUrl = null,
}) {
  const r = await q(
    `INSERT INTO company_expense_claim
       (employee_user_id, category, amount_iqd, expense_date, reason, receipt_url)
     VALUES ($1,$2,$3,COALESCE($4, CURRENT_DATE),$5,$6)
     RETURNING *`,
    [Number(employeeUserId), category, Number(amountIqd), expenseDate, reason, receiptUrl]
  );
  return r.rows[0];
}

export async function listMyExpenses({ employeeUserId, limit = 50 }) {
  const r = await q(
    `SELECT * FROM company_expense_claim
     WHERE employee_user_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [Number(employeeUserId), Math.max(1, Math.min(200, Number(limit) || 50))]
  );
  return r.rows;
}

export async function adminListExpenses({ status = null, limit = 100 }) {
  const params = [];
  let where = "";
  if (status) {
    params.push(String(status));
    where = `WHERE e.status = $${params.length}`;
  }
  params.push(Math.max(1, Math.min(500, Number(limit) || 100)));
  const r = await q(
    `SELECT e.*, u.full_name
     FROM company_expense_claim e JOIN app_user u ON u.id = e.employee_user_id
     ${where}
     ORDER BY e.created_at DESC LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function reviewExpense({ expenseId, status, reviewedByUserId }) {
  const r = await q(
    `UPDATE company_expense_claim
     SET status = $2, reviewed_by_user_id = $3, reviewed_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND status = 'submitted'
     RETURNING *`,
    [Number(expenseId), status, reviewedByUserId ? Number(reviewedByUserId) : null]
  );
  if (!r.rows[0]) return { code: "NOT_REVIEWABLE" };
  return { code: "OK", expense: r.rows[0] };
}
