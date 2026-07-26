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
          start_date, base_salary_iqd, notes, created_by_user_id, updated_by_user_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$10)
       ON CONFLICT (user_id) DO UPDATE SET
         department = EXCLUDED.department,
         job_title = EXCLUDED.job_title,
         employment_type = EXCLUDED.employment_type,
         manager_user_id = EXCLUDED.manager_user_id,
         status = EXCLUDED.status,
         start_date = COALESCE(EXCLUDED.start_date, company_employee_profile.start_date),
         notes = EXCLUDED.notes,
         updated_by_user_id = EXCLUDED.updated_by_user_id,
         updated_at = NOW()
       RETURNING *`,
      [
        Number(userId), department, jobTitle, employmentType,
        managerUserId ? Number(managerUserId) : null, status, startDate,
        baseSalaryIqd != null ? Number(baseSalaryIqd) : null, notes,
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
