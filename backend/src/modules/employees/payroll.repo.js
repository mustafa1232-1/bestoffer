/**
 * Purpose:
 * دورة الرواتب لموظفي الشركة (المرحلة 7). حساب البنود من الراتب الأساسي +
 * المصاريف المعتمدة، وانتقالات حالة ذرية مع أختام الفاعل.
 */

import { pool, q } from "../../config/db.js";
import { canPayrollTransition, canRecalculate, computeNet } from "./payroll.policy.js";

export async function createRun({ periodMonth, createdByUserId, notes = null }) {
  try {
    const r = await q(
      `INSERT INTO company_payroll_run (period_month, created_by_user_id, notes)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [String(periodMonth), createdByUserId ? Number(createdByUserId) : null, notes]
    );
    return { code: "OK", run: r.rows[0] };
  } catch (error) {
    if (error?.code === "23505") return { code: "PERIOD_EXISTS" };
    throw error;
  }
}

export async function getRun(runId) {
  const run = await q(`SELECT * FROM company_payroll_run WHERE id = $1`, [Number(runId)]);
  if (!run.rows[0]) return null;
  const items = await q(
    `SELECT i.*, u.full_name
     FROM company_payroll_item i JOIN app_user u ON u.id = i.employee_user_id
     WHERE i.run_id = $1
     ORDER BY u.full_name ASC`,
    [Number(runId)]
  );
  return { run: run.rows[0], items: items.rows };
}

export async function listRuns({ limit = 24 } = {}) {
  const r = await q(
    `SELECT * FROM company_payroll_run
     ORDER BY period_month DESC LIMIT $1`,
    [Math.max(1, Math.min(60, Number(limit) || 24))]
  );
  return r.rows;
}

/**
 * يعيد بناء بنود الدورة من رواتب الموظفين النشطين + المصاريف المعتمدة للشهر.
 * مسموح فقط في DRAFT/CALCULATED.
 */
export async function calculateRun({ runId, actorUserId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT * FROM company_payroll_run WHERE id = $1 FOR UPDATE`,
      [Number(runId)]
    );
    const run = lock.rows[0];
    if (!run) {
      await client.query("ROLLBACK");
      return { code: "RUN_NOT_FOUND" };
    }
    if (!canRecalculate(run.status)) {
      await client.query("ROLLBACK");
      return { code: "NOT_RECALCULABLE", currentStatus: run.status };
    }

    await client.query(`DELETE FROM company_payroll_item WHERE run_id = $1`, [Number(runId)]);

    const employees = await client.query(
      `SELECT e.user_id, COALESCE(e.base_salary_iqd, 0) AS base
       FROM company_employee_profile e
       WHERE e.status = 'active'`
    );

    for (const emp of employees.rows) {
      const expenses = await client.query(
        `SELECT COALESCE(SUM(amount_iqd), 0)::int AS total
         FROM company_expense_claim
         WHERE employee_user_id = $1
           AND status = 'approved'
           AND to_char(expense_date, 'YYYY-MM') = $2`,
        [Number(emp.user_id), run.period_month]
      );
      const additions = Number(expenses.rows[0]?.total || 0);
      const base = Number(emp.base || 0);
      const net = computeNet({ baseSalaryIqd: base, additionsIqd: additions, deductionsIqd: 0 });
      await client.query(
        `INSERT INTO company_payroll_item
           (run_id, employee_user_id, base_salary_iqd, additions_iqd, deductions_iqd, net_iqd, breakdown)
         VALUES ($1,$2,$3,$4,0,$5,$6::jsonb)`,
        [
          Number(runId), Number(emp.user_id), base, additions, net,
          JSON.stringify({ approvedExpenses: additions }),
        ]
      );
    }

    // اربط المصاريف المعتمدة للشهر بهذه الدورة.
    await client.query(
      `UPDATE company_expense_claim
       SET status = 'included_in_payroll', payroll_run_id = $1, updated_at = NOW()
       WHERE status = 'approved'
         AND to_char(expense_date, 'YYYY-MM') = $2`,
      [Number(runId), run.period_month]
    );

    const upd = await client.query(
      `UPDATE company_payroll_run
       SET status = 'CALCULATED', calculated_at = NOW(), updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [Number(runId)]
    );
    await client.query("COMMIT");
    return { code: "OK", run: upd.rows[0], employeeCount: employees.rows.length };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

const STATUS_STAMP = {
  UNDER_REVIEW: { col: "submitted_by_user_id" },
  APPROVED: { col: "approved_by_user_id", at: "approved_at" },
  RELEASED: { col: "released_by_user_id", at: "released_at" },
  PAID: { col: "paid_by_user_id", at: "paid_at" },
  ARCHIVED: { at: "archived_at" },
};

/**
 * انتقال حالة دورة الراتب ذرياً. يدعم مبدأ المُراجع الثاني: عند requireDistinct
 * لا يجوز أن يكون مَن يوافق هو نفسه مَن قدّم للمراجعة.
 */
export async function transitionRun({
  runId, toStatus, actorUserId, requireDistinctApprover = false,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT * FROM company_payroll_run WHERE id = $1 FOR UPDATE`,
      [Number(runId)]
    );
    const run = lock.rows[0];
    if (!run) {
      await client.query("ROLLBACK");
      return { code: "RUN_NOT_FOUND" };
    }
    if (!canPayrollTransition(run.status, toStatus)) {
      await client.query("ROLLBACK");
      return { code: "INVALID_TRANSITION", currentStatus: run.status };
    }
    if (
      requireDistinctApprover &&
      toStatus === "APPROVED" &&
      run.submitted_by_user_id != null &&
      Number(run.submitted_by_user_id) === Number(actorUserId)
    ) {
      await client.query("ROLLBACK");
      return { code: "SEPARATION_OF_DUTIES" };
    }

    const sets = ["status = $2", "updated_at = NOW()"];
    const params = [Number(runId), toStatus];
    const stamp = STATUS_STAMP[toStatus];
    if (stamp?.col) {
      params.push(actorUserId ? Number(actorUserId) : null);
      sets.push(`${stamp.col} = $${params.length}`);
    }
    if (stamp?.at) sets.push(`${stamp.at} = NOW()`);

    const upd = await client.query(
      `UPDATE company_payroll_run SET ${sets.join(", ")} WHERE id = $1 RETURNING *`,
      params
    );
    await client.query("COMMIT");
    return { code: "OK", run: upd.rows[0], previousStatus: run.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function acknowledgeItem({ runId, employeeUserId }) {
  const r = await q(
    `UPDATE company_payroll_item
     SET acknowledged_at = NOW()
     WHERE run_id = $1 AND employee_user_id = $2
     RETURNING *`,
    [Number(runId), Number(employeeUserId)]
  );
  if (!r.rows[0]) return { code: "ITEM_NOT_FOUND" };
  return { code: "OK", item: r.rows[0] };
}

export async function listItemsForEmployee({ employeeUserId, limit = 24 }) {
  const r = await q(
    `SELECT i.*, r.period_month, r.status AS run_status
     FROM company_payroll_item i JOIN company_payroll_run r ON r.id = i.run_id
     WHERE i.employee_user_id = $1
       AND r.status IN ('RELEASED','PAID','ACKNOWLEDGED','ARCHIVED')
     ORDER BY r.period_month DESC LIMIT $2`,
    [Number(employeeUserId), Math.max(1, Math.min(60, Number(limit) || 24))]
  );
  return r.rows;
}
