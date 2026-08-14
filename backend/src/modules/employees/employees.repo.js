/**
 * Purpose:
 * إدارة موظفي مسلكي (الشركة) — المرحلة 6. منفصلة عن موظفي المتاجر (merchant_*).
 * إنشاء/تعديل الموظف يضع is_internal_staff=TRUE (عزل عن المجتمع، يُفرض في Backend).
 */

import { pool, q } from "../../config/db.js";

export const DEPARTMENTS = Object.freeze([
  "delivery", "customer_service", "hr", "monitoring", "accounting",
  "marketing", "management", "tech", "other",
]);
export const EMPLOYMENT_TYPES = Object.freeze([
  "full_time", "part_time", "contract", "temporary",
]);
export const EMPLOYEE_STATUSES = Object.freeze(["active", "suspended", "terminated"]);

export async function getEmployeeByUserId(userId) {
  const r = await q(
    `SELECT e.*, u.full_name, u.phone, u.username, u.is_internal_staff,
            u.admin_role_key, u.permission_version,
            m.full_name AS manager_name
     FROM company_employee_profile e
     JOIN app_user u ON u.id = e.user_id
     LEFT JOIN app_user m ON m.id = e.manager_user_id
     WHERE e.user_id = $1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listEmployees({
  department = null,
  status = null,
  search = null,
  limit = 25,
  offset = 0,
} = {}) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 25));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const conds = [];
  const params = [];
  if (department) {
    params.push(String(department));
    conds.push(`e.department = $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    conds.push(`e.status = $${params.length}`);
  }
  if (search) {
    params.push(`%${String(search).trim()}%`);
    conds.push(`(u.full_name ILIKE $${params.length} OR u.phone ILIKE $${params.length})`);
  }
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM company_employee_profile e JOIN app_user u ON u.id = e.user_id ${where}`,
    params
  );
  params.push(safeLimit);
  params.push(safeOffset);
  const rows = await q(
    `SELECT e.id, e.user_id, e.department, e.job_title, e.employment_type,
            e.status, e.start_date, e.base_salary_iqd, e.manager_user_id,
            u.full_name, u.phone
     FROM company_employee_profile e JOIN app_user u ON u.id = e.user_id
     ${where}
     ORDER BY e.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: safeLimit,
    offset: safeOffset,
    items: rows.rows,
  };
}

export async function upsertEmployee({
  userId,
  department,
  jobTitle = null,
  employmentType = "full_time",
  managerUserId = null,
  status = "active",
  startDate = null,
  baseSalaryIqd = null,
  notes = null,
  employeeCode = null,
  actorUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const before = await client.query(
      `SELECT * FROM company_employee_profile WHERE user_id = $1`,
      [Number(userId)]
    );
    const upserted = await client.query(
      `INSERT INTO company_employee_profile
         (user_id, department, job_title, employment_type, manager_user_id, status,
          start_date, base_salary_iqd, notes, employee_code, created_by_user_id, updated_by_user_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)
       ON CONFLICT (user_id) DO UPDATE SET
         department = EXCLUDED.department,
         job_title = EXCLUDED.job_title,
         employment_type = EXCLUDED.employment_type,
         manager_user_id = EXCLUDED.manager_user_id,
         status = EXCLUDED.status,
         start_date = COALESCE(EXCLUDED.start_date, company_employee_profile.start_date),
         notes = EXCLUDED.notes,
         employee_code = COALESCE(EXCLUDED.employee_code, company_employee_profile.employee_code),
         updated_by_user_id = EXCLUDED.updated_by_user_id,
         updated_at = NOW()
       RETURNING *`,
      [
        Number(userId), department, jobTitle, employmentType,
        managerUserId ? Number(managerUserId) : null, status, startDate,
        baseSalaryIqd != null ? Number(baseSalaryIqd) : null, notes,
        employeeCode || null,
        actorUserId ? Number(actorUserId) : null,
      ]
    );
    // عزل الموظف عن المجتمع.
    await client.query(
      `UPDATE app_user SET is_internal_staff = TRUE WHERE id = $1`,
      [Number(userId)]
    );
    // عقد راتب أولي عند تحديد راتب لأول مرة.
    if (baseSalaryIqd != null && !before.rows[0]) {
      await client.query(
        `INSERT INTO company_salary_contract
           (employee_user_id, base_salary_iqd, effective_from, reason, created_by_user_id)
         VALUES ($1,$2,COALESCE($3, CURRENT_DATE),'initial',$4)`,
        [Number(userId), Number(baseSalaryIqd), startDate, actorUserId ? Number(actorUserId) : null]
      );
    }
    await client.query("COMMIT");
    return { employee: upserted.rows[0], created: !before.rows[0], before: before.rows[0] || null };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

// The signed-in employee's own dashboard: profile + current/earned salary +
// this-month attendance summary + salary history. Self-scoped (no admin perm).
export async function getMyEmployeeDashboard(userId) {
  const id = Number(userId);
  const profileRes = await q(
    `SELECT p.user_id, u.full_name, u.phone, u.admin_role_key,
            p.department, p.job_title, p.employment_type, p.status,
            p.base_salary_iqd, p.employee_code, p.start_date
     FROM company_employee_profile p
     JOIN app_user u ON u.id = p.user_id
     WHERE p.user_id = $1`,
    [id]
  );
  const profile = profileRes.rows[0];
  if (!profile) return null;

  const salaryHistory = (
    await q(
      `SELECT base_salary_iqd, effective_from, reason
       FROM company_salary_contract
       WHERE employee_user_id = $1
       ORDER BY effective_from DESC, id DESC
       LIMIT 12`,
      [id]
    )
  ).rows;

  const att = (
    await q(
      `SELECT
         COUNT(DISTINCT ((check_in_at AT TIME ZONE 'Asia/Baghdad')::date)) AS present_days,
         COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(check_out_at, NOW()) - check_in_at))) / 3600.0, 0) AS hours,
         MAX(check_in_at) AS last_check_in,
         BOOL_OR(check_out_at IS NULL) AS currently_in
       FROM company_attendance
       WHERE employee_user_id = $1
         AND (check_in_at AT TIME ZONE 'Asia/Baghdad')
             >= date_trunc('month', (NOW() AT TIME ZONE 'Asia/Baghdad'))`,
      [id]
    )
  ).rows[0];

  const monthlySalary = Number(profile.base_salary_iqd || 0);
  const presentDays = Number(att.present_days || 0);
  const dailyRate = monthlySalary > 0 ? monthlySalary / 30 : 0;
  const earnedThisMonth = Math.round(dailyRate * presentDays);

  return {
    profile: {
      userId: Number(profile.user_id),
      fullName: profile.full_name,
      phone: profile.phone,
      jobRoleKey: profile.admin_role_key || null,
      department: profile.department,
      jobTitle: profile.job_title,
      employmentType: profile.employment_type,
      status: profile.status,
      employeeCode: profile.employee_code,
      startDate: profile.start_date,
    },
    salary: {
      monthlySalaryIqd: monthlySalary,
      dailyRateIqd: Math.round(dailyRate),
      earnedThisMonthIqd: earnedThisMonth,
    },
    attendance: {
      presentDaysThisMonth: presentDays,
      hoursThisMonth: Math.round(Number(att.hours || 0) * 10) / 10,
      lastCheckIn: att.last_check_in,
      currentlyCheckedIn: att.currently_in === true,
    },
    salaryHistory: salaryHistory.map((r) => ({
      baseSalaryIqd: Number(r.base_salary_iqd || 0),
      effectiveFrom: r.effective_from,
      reason: r.reason || null,
    })),
  };
}

export async function getEmployeeOperationalSummary(userId) {
  const id = Number(userId);
  const [attendanceRes, expenseRes, payrollRes] = await Promise.all([
    q(
      `WITH bounds AS (
         SELECT
           GREATEST(
             date_trunc('month', (NOW() AT TIME ZONE 'Asia/Baghdad'))::date,
             COALESCE(e.start_date, date_trunc('month', (NOW() AT TIME ZONE 'Asia/Baghdad'))::date)
           ) AS start_date,
           (NOW() AT TIME ZONE 'Asia/Baghdad')::date AS today
         FROM company_employee_profile e
         WHERE e.user_id = $1
       ),
       current_month AS (
         SELECT
           COUNT(DISTINCT ((a.check_in_at AT TIME ZONE 'Asia/Baghdad')::date))::int AS present_days,
           COUNT(*)::int AS sessions,
           COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(a.check_out_at, NOW()) - a.check_in_at))) / 3600.0, 0) AS hours,
           BOOL_OR(a.check_out_at IS NULL) AS currently_in,
           MAX(a.check_in_at) AS last_check_in
         FROM company_attendance a, bounds b
         WHERE a.employee_user_id = $1
           AND ((a.check_in_at AT TIME ZONE 'Asia/Baghdad')::date) BETWEEN b.start_date AND b.today
       ),
       lifetime AS (
         SELECT
           COUNT(DISTINCT ((a.check_in_at AT TIME ZONE 'Asia/Baghdad')::date))::int AS present_days_total,
           COUNT(*)::int AS sessions_total
         FROM company_attendance a
         WHERE a.employee_user_id = $1
       )
       SELECT
         COALESCE(cm.present_days, 0)::int AS present_days_this_month,
         GREATEST(0, ((b.today - b.start_date + 1)::int - COALESCE(cm.present_days, 0)))::int AS absent_days_this_month,
         COALESCE(cm.sessions, 0)::int AS sessions_this_month,
         ROUND(COALESCE(cm.hours, 0)::numeric, 1)::float AS hours_this_month,
         COALESCE(cm.currently_in, FALSE) AS currently_checked_in,
         cm.last_check_in,
         COALESCE(lt.present_days_total, 0)::int AS present_days_total,
         COALESCE(lt.sessions_total, 0)::int AS sessions_total
       FROM bounds b
       CROSS JOIN current_month cm
       CROSS JOIN lifetime lt`,
      [id]
    ),
    q(
      `SELECT
         status,
         COUNT(*)::int AS count,
         COALESCE(SUM(amount_iqd), 0)::int AS amount_iqd
       FROM company_expense_claim
       WHERE employee_user_id = $1
       GROUP BY status`,
      [id]
    ),
    q(
      `SELECT
         r.id AS run_id,
         r.period_month,
         r.status AS run_status,
         i.base_salary_iqd,
         i.additions_iqd,
         i.deductions_iqd,
         i.net_iqd,
         i.breakdown,
         i.acknowledged_at,
         i.created_at
       FROM company_payroll_item i
       JOIN company_payroll_run r ON r.id = i.run_id
       WHERE i.employee_user_id = $1
       ORDER BY r.period_month DESC, r.id DESC
       LIMIT 1`,
      [id]
    ),
  ]);

  const expensesByStatus = {};
  for (const row of expenseRes.rows) {
    expensesByStatus[row.status] = {
      count: Number(row.count || 0),
      amountIqd: Number(row.amount_iqd || 0),
    };
  }

  const latestPayroll = payrollRes.rows[0] || null;
  return {
    attendance: attendanceRes.rows[0] || null,
    expensesByStatus,
    latestPayroll: latestPayroll
      ? {
          runId: Number(latestPayroll.run_id),
          periodMonth: latestPayroll.period_month,
          runStatus: latestPayroll.run_status,
          baseSalaryIqd: Number(latestPayroll.base_salary_iqd || 0),
          additionsIqd: Number(latestPayroll.additions_iqd || 0),
          deductionsIqd: Number(latestPayroll.deductions_iqd || 0),
          netIqd: Number(latestPayroll.net_iqd || 0),
          breakdown: latestPayroll.breakdown || {},
          acknowledgedAt: latestPayroll.acknowledged_at || null,
          createdAt: latestPayroll.created_at || null,
        }
      : null,
  };
}

// Compensating delete for a half-created employee account (role must be 'staff'
// so this can never remove a real user/admin). Profile + salary contracts cascade.
export async function deleteStaffAccount(userId) {
  const r = await q(
    `DELETE FROM app_user WHERE id = $1 AND role = 'staff'`,
    [Number(userId)]
  );
  return r.rowCount > 0;
}

export async function setSalary({
  userId,
  baseSalaryIqd,
  effectiveFrom,
  reason = null,
  actorUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const contract = await client.query(
      `INSERT INTO company_salary_contract
         (employee_user_id, base_salary_iqd, effective_from, reason, created_by_user_id)
       VALUES ($1,$2,$3,$4,$5)
       RETURNING *`,
      [
        Number(userId), Number(baseSalaryIqd), effectiveFrom, reason,
        actorUserId ? Number(actorUserId) : null,
      ]
    );
    await client.query(
      `UPDATE company_employee_profile
       SET base_salary_iqd = $2, updated_by_user_id = $3, updated_at = NOW()
       WHERE user_id = $1`,
      [Number(userId), Number(baseSalaryIqd), actorUserId ? Number(actorUserId) : null]
    );
    await client.query("COMMIT");
    return contract.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function lookupUsers({ search = "", limit = 15 } = {}) {
  const term = String(search || "").trim();
  if (!term) return [];
  const digits = term.replace(/[^\d]/g, "");
  const like = `%${term}%`;
  const r = await q(
    `SELECT u.id, u.full_name, u.phone, u.role,
            COALESCE(u.is_internal_staff, FALSE) AS is_internal_staff,
            (e.user_id IS NOT NULL) AS is_employee
     FROM app_user u
     LEFT JOIN company_employee_profile e ON e.user_id = u.id
     WHERE COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         u.full_name ILIKE $1
         OR u.phone ILIKE $1
         OR ($2 <> '' AND regexp_replace(COALESCE(u.phone,''),'\\D','','g') LIKE ('%' || $2 || '%'))
       )
     ORDER BY (e.user_id IS NOT NULL) ASC, u.full_name ASC
     LIMIT $3`,
    [like, digits, Math.max(1, Math.min(50, Number(limit) || 15))]
  );
  return r.rows;
}

export async function listSalaryHistory(userId) {
  const r = await q(
    `SELECT id, base_salary_iqd, effective_from, reason, created_at
     FROM company_salary_contract
     WHERE employee_user_id = $1
     ORDER BY effective_from DESC, id DESC`,
    [Number(userId)]
  );
  return r.rows;
}
