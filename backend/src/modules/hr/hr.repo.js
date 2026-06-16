import { pool, q } from "../../config/db.js";

function clampLimit(value, fallback = 100) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  if (parsed < 1) return 1;
  if (parsed > 300) return 300;
  return parsed;
}

function toNullableDate(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

function monthBounds(periodYear, periodMonth) {
  const year = Number(periodYear);
  const month = Number(periodMonth);
  if (!Number.isInteger(year) || !Number.isInteger(month)) {
    return null;
  }
  if (year < 2000 || year > 2100 || month < 1 || month > 12) {
    return null;
  }
  const from = new Date(Date.UTC(year, month - 1, 1));
  const to = new Date(Date.UTC(year, month, 0));
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
  };
}

export async function findHrMerchantByUserId(hrUserId) {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.owner_user_id
     FROM merchant_hr_staff hs
     JOIN merchant m ON m.id = hs.merchant_id
     WHERE hs.hr_user_id = $1
       AND hs.is_active = TRUE
       AND m.is_disabled = FALSE
     ORDER BY hs.updated_at DESC, hs.created_at DESC
     LIMIT 1`,
    [Number(hrUserId)]
  );
  return r.rows[0] || null;
}

export async function findDeliveryMerchantByUserId(deliveryUserId) {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.owner_user_id
     FROM merchant_delivery_agent da
     JOIN merchant m ON m.id = da.merchant_id
     WHERE da.delivery_user_id = $1
       AND da.is_active = TRUE
       AND m.is_disabled = FALSE
     ORDER BY da.updated_at DESC, da.created_at DESC
     LIMIT 1`,
    [Number(deliveryUserId)]
  );
  return r.rows[0] || null;
}

export async function findAccountantMerchantByUserId(accountantUserId) {
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

export async function findOwnerMerchantByUserId(ownerUserId) {
  const r = await q(
    `SELECT id, name, type, owner_user_id
     FROM merchant
     WHERE owner_user_id = $1
       AND is_disabled = FALSE
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function findMerchantById(merchantId) {
  const r = await q(
    `SELECT id, name, type, owner_user_id, is_disabled
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listMerchantEmployees({
  merchantId,
  search = "",
  limit = 120,
}) {
  const safeLimit = clampLimit(limit, 120);
  const normalizedSearch = String(search || "").trim();
  const params = [Number(merchantId)];
  let searchClause = "";
  if (normalizedSearch) {
    params.push(`%${normalizedSearch}%`);
    searchClause =
      "AND (u.full_name ILIKE $2 OR regexp_replace(u.phone, '[^0-9]', '', 'g') ILIKE $2)";
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `WITH scoped_users AS (
       SELECT m.owner_user_id AS user_id
       FROM merchant m
       WHERE m.id = $1
         AND m.owner_user_id IS NOT NULL
       UNION
       SELECT mda.delivery_user_id AS user_id
       FROM merchant_delivery_agent mda
       WHERE mda.merchant_id = $1
         AND mda.is_active = TRUE
       UNION
       SELECT ma.accountant_user_id AS user_id
       FROM merchant_accountant ma
       WHERE ma.merchant_id = $1
         AND ma.is_active = TRUE
       UNION
       SELECT hs.hr_user_id AS user_id
       FROM merchant_hr_staff hs
       WHERE hs.merchant_id = $1
         AND hs.is_active = TRUE
       UNION
       SELECT ep.employee_user_id AS user_id
       FROM merchant_employee_profile ep
       WHERE ep.merchant_id = $1
     )
     SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.work_title,
       u.work_company,
       ep.id AS employee_profile_id,
       ep.role_tag,
       ep.employment_type,
       ep.base_salary,
       ep.currency,
       ep.work_days_per_week,
       ep.shift_start_time,
       ep.shift_end_time,
       ep.joined_at,
       ep.is_active AS profile_is_active,
       ep.notes,
       EXISTS (
         SELECT 1
         FROM merchant_delivery_agent mda
         WHERE mda.merchant_id = $1
           AND mda.delivery_user_id = u.id
           AND mda.is_active = TRUE
       ) AS is_delivery_agent,
       EXISTS (
         SELECT 1
         FROM merchant_accountant ma
         WHERE ma.merchant_id = $1
           AND ma.accountant_user_id = u.id
           AND ma.is_active = TRUE
       ) AS is_accountant,
       EXISTS (
         SELECT 1
         FROM merchant_hr_staff hs
         WHERE hs.merchant_id = $1
           AND hs.hr_user_id = u.id
           AND hs.is_active = TRUE
       ) AS is_hr_staff
     FROM app_user u
     JOIN (SELECT DISTINCT user_id FROM scoped_users) su ON su.user_id = u.id
     LEFT JOIN merchant_employee_profile ep
       ON ep.merchant_id = $1
      AND ep.employee_user_id = u.id
     WHERE u.is_account_disabled = FALSE
       ${searchClause}
     ORDER BY
       COALESCE(ep.role_tag::text, u.role::text) ASC,
       u.full_name ASC,
       u.id DESC
     LIMIT $${limitIndex}`,
    params
  );

  return r.rows;
}

export async function getDashboardStats(merchantId) {
  const [employees, attendanceToday, payroll, jobs] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total_employees,
         COALESCE(SUM(CASE WHEN is_active THEN 1 ELSE 0 END), 0)::int AS active_profiles
       FROM merchant_employee_profile
       WHERE merchant_id = $1`,
      [Number(merchantId)]
    ),
    q(
      `SELECT
         COALESCE(SUM(CASE WHEN status IN ('present', 'late', 'half_day') THEN 1 ELSE 0 END), 0)::int AS present_count,
         COALESCE(SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END), 0)::int AS absent_count,
         COALESCE(SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END), 0)::int AS leave_count
       FROM merchant_attendance_log
       WHERE merchant_id = $1
         AND attendance_date = CURRENT_DATE`,
      [Number(merchantId)]
    ),
    q(
      `SELECT
         COUNT(*)::int AS total_batches,
         COALESCE(SUM(CASE WHEN status IN ('draft', 'submitted', 'processing') THEN 1 ELSE 0 END), 0)::int AS open_batches
       FROM merchant_payroll_batch
       WHERE merchant_id = $1`,
      [Number(merchantId)]
    ),
    q(
      `SELECT
         COUNT(*)::int AS total_open_jobs
       FROM job_post
       WHERE merchant_id = $1
         AND status = 'active'
         AND (expires_at IS NULL OR expires_at >= NOW())`,
      [Number(merchantId)]
    ),
  ]);

  return {
    totalEmployees: Number(employees.rows[0]?.total_employees || 0),
    activeProfiles: Number(employees.rows[0]?.active_profiles || 0),
    presentToday: Number(attendanceToday.rows[0]?.present_count || 0),
    absentToday: Number(attendanceToday.rows[0]?.absent_count || 0),
    leaveToday: Number(attendanceToday.rows[0]?.leave_count || 0),
    totalPayrollBatches: Number(payroll.rows[0]?.total_batches || 0),
    openPayrollBatches: Number(payroll.rows[0]?.open_batches || 0),
    totalOpenJobs: Number(jobs.rows[0]?.total_open_jobs || 0),
  };
}

export async function upsertEmployeeProfile({
  merchantId,
  employeeUserId,
  roleTag,
  employmentType,
  baseSalary,
  currency,
  workDaysPerWeek,
  shiftStartTime,
  shiftEndTime,
  joinedAt,
  isActive,
  notes,
  updatedByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_employee_profile
      (
        merchant_id,
        employee_user_id,
        role_tag,
        employment_type,
        base_salary,
        currency,
        work_days_per_week,
        shift_start_time,
        shift_end_time,
        joined_at,
        is_active,
        notes,
        updated_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,NOW(),NOW())
     ON CONFLICT (merchant_id, employee_user_id)
     DO UPDATE SET
       role_tag = EXCLUDED.role_tag,
       employment_type = EXCLUDED.employment_type,
       base_salary = EXCLUDED.base_salary,
       currency = EXCLUDED.currency,
       work_days_per_week = EXCLUDED.work_days_per_week,
       shift_start_time = EXCLUDED.shift_start_time,
       shift_end_time = EXCLUDED.shift_end_time,
       joined_at = EXCLUDED.joined_at,
       is_active = EXCLUDED.is_active,
       notes = EXCLUDED.notes,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(merchantId),
      Number(employeeUserId),
      String(roleTag || "staff").slice(0, 80),
      String(employmentType || "full_time").slice(0, 32),
      Number(baseSalary || 0),
      String(currency || "IQD").slice(0, 10),
      Math.max(1, Math.min(7, Number(workDaysPerWeek || 6))),
      shiftStartTime || null,
      shiftEndTime || null,
      toNullableDate(joinedAt),
      isActive !== false,
      notes ? String(notes).slice(0, 3000) : null,
      Number(updatedByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listAttendanceLogs({
  merchantId,
  employeeUserId = null,
  dateFrom = null,
  dateTo = null,
  limit = 200,
}) {
  const safeLimit = clampLimit(limit, 200);
  const params = [Number(merchantId)];
  const clauses = ["al.merchant_id = $1"];

  if (employeeUserId != null) {
    params.push(Number(employeeUserId));
    clauses.push(`al.employee_user_id = $${params.length}`);
  }
  if (dateFrom) {
    params.push(toNullableDate(dateFrom));
    clauses.push(`al.attendance_date >= $${params.length}`);
  }
  if (dateTo) {
    params.push(toNullableDate(dateTo));
    clauses.push(`al.attendance_date <= $${params.length}`);
  }

  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       al.id,
       al.merchant_id,
       al.employee_user_id,
       al.attendance_date,
       al.check_in_at,
       al.check_out_at,
       al.check_in_image_url,
       al.check_out_image_url,
       al.status,
       al.source,
       al.note,
       al.recorded_by_user_id,
       al.created_at,
       al.updated_at,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone
     FROM merchant_attendance_log al
     JOIN app_user u ON u.id = al.employee_user_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY al.attendance_date DESC, al.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function upsertAttendanceLog({
  merchantId,
  employeeUserId,
  attendanceDate,
  checkInAt,
  checkOutAt,
  checkInImageUrl,
  checkOutImageUrl,
  status,
  source = "manual",
  note,
  recordedByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_attendance_log
      (
        merchant_id,
        employee_user_id,
        attendance_date,
        check_in_at,
        check_out_at,
        check_in_image_url,
        check_out_image_url,
        status,
        source,
        note,
        recorded_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,NOW(),NOW())
     ON CONFLICT (merchant_id, employee_user_id, attendance_date)
     DO UPDATE SET
       check_in_at = COALESCE(EXCLUDED.check_in_at, merchant_attendance_log.check_in_at),
       check_out_at = COALESCE(EXCLUDED.check_out_at, merchant_attendance_log.check_out_at),
       check_in_image_url = COALESCE(EXCLUDED.check_in_image_url, merchant_attendance_log.check_in_image_url),
       check_out_image_url = COALESCE(EXCLUDED.check_out_image_url, merchant_attendance_log.check_out_image_url),
       status = EXCLUDED.status,
       source = EXCLUDED.source,
       note = EXCLUDED.note,
       recorded_by_user_id = EXCLUDED.recorded_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(merchantId),
      Number(employeeUserId),
      toNullableDate(attendanceDate),
      checkInAt || null,
      checkOutAt || null,
      checkInImageUrl || null,
      checkOutImageUrl || null,
      String(status || "present").slice(0, 24),
      String(source || "manual").slice(0, 24),
      note ? String(note).slice(0, 3000) : null,
      Number(recordedByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function findEmployeeProfileForMerchant({
  merchantId,
  employeeUserId,
}) {
  const r = await q(
    `SELECT *
     FROM merchant_employee_profile
     WHERE merchant_id = $1
       AND employee_user_id = $2
     LIMIT 1`,
    [Number(merchantId), Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function listEmployeeProfilesByUserId(userId) {
  const r = await q(
    `SELECT
       ep.*,
       m.name AS merchant_name,
       m.type AS merchant_type
     FROM merchant_employee_profile ep
     JOIN merchant m ON m.id = ep.merchant_id
     WHERE ep.employee_user_id = $1
       AND ep.is_active = TRUE
       AND m.is_disabled = FALSE
     ORDER BY ep.updated_at DESC, ep.id DESC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function listActiveEmployeeProfiles(merchantId) {
  const r = await q(
    `SELECT
       ep.*,
       u.full_name,
       u.phone,
       u.image_url
     FROM merchant_employee_profile ep
     JOIN app_user u ON u.id = ep.employee_user_id
     WHERE ep.merchant_id = $1
       AND ep.is_active = TRUE
       AND u.is_account_disabled = FALSE
     ORDER BY ep.role_tag ASC, u.full_name ASC, ep.employee_user_id ASC`,
    [Number(merchantId)]
  );
  return r.rows;
}

export async function createOrReusePayrollBatch({
  merchantId,
  periodYear,
  periodMonth,
  summaryNote,
  createdByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_payroll_batch
      (
        merchant_id,
        period_year,
        period_month,
        status,
        summary_note,
        created_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,'draft',$4,$5,NOW(),NOW())
     ON CONFLICT (merchant_id, period_year, period_month)
     DO UPDATE SET
       summary_note = COALESCE(EXCLUDED.summary_note, merchant_payroll_batch.summary_note),
       updated_at = NOW()
     RETURNING *`,
    [
      Number(merchantId),
      Number(periodYear),
      Number(periodMonth),
      summaryNote ? String(summaryNote).slice(0, 3000) : null,
      Number(createdByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listPayrollBatches({
  merchantId,
  limit = 40,
  status = null,
}) {
  const safeLimit = clampLimit(limit, 40);
  const params = [Number(merchantId)];
  const clauses = ["pb.merchant_id = $1"];
  if (status) {
    params.push(String(status));
    clauses.push(`pb.status = $${params.length}`);
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       pb.*,
       COALESCE(COUNT(pi.id), 0)::int AS employees_count,
       COALESCE(SUM(pi.net_salary), 0) AS total_net_salary,
       COALESCE(SUM(CASE WHEN pi.status = 'paid' THEN pi.net_salary ELSE 0 END), 0) AS total_paid_salary,
       COALESCE(SUM(CASE WHEN pi.status = 'pending' THEN pi.net_salary ELSE 0 END), 0) AS total_pending_salary
     FROM merchant_payroll_batch pb
     LEFT JOIN merchant_payroll_item pi ON pi.batch_id = pb.id
     WHERE ${clauses.join(" AND ")}
     GROUP BY pb.id
     ORDER BY pb.period_year DESC, pb.period_month DESC, pb.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function findPayrollBatchById({ merchantId, batchId }) {
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

export async function upsertPayrollItem({
  batchId,
  merchantId,
  employeeUserId,
  baseSalary,
  bonuses,
  deductions,
  leaveAdjustment,
  netSalary,
  hrNote,
}) {
  const r = await q(
    `INSERT INTO merchant_payroll_item
      (
        batch_id,
        merchant_id,
        employee_user_id,
        base_salary,
        bonuses,
        deductions,
        leave_adjustment,
        net_salary,
        status,
        hr_note,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'pending',$9,NOW(),NOW())
     ON CONFLICT (batch_id, employee_user_id)
     DO UPDATE SET
       base_salary = EXCLUDED.base_salary,
       bonuses = EXCLUDED.bonuses,
       deductions = EXCLUDED.deductions,
       leave_adjustment = EXCLUDED.leave_adjustment,
       net_salary = EXCLUDED.net_salary,
       hr_note = EXCLUDED.hr_note,
       status = CASE
         WHEN merchant_payroll_item.status = 'paid' THEN merchant_payroll_item.status
         ELSE 'pending'
       END,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(batchId),
      Number(merchantId),
      Number(employeeUserId),
      Number(baseSalary || 0),
      Number(bonuses || 0),
      Number(deductions || 0),
      Number(leaveAdjustment || 0),
      Number(netSalary || 0),
      hrNote ? String(hrNote).slice(0, 3000) : null,
    ]
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

export async function updatePayrollBatchStatus({
  merchantId,
  batchId,
  status,
  actorUserId,
}) {
  const updateParts = ["status = $3", "updated_at = NOW()"];
  const values = [Number(batchId), Number(merchantId), String(status)];

  if (status === "submitted") {
    updateParts.push("acknowledged_by_user_id = NULL");
    updateParts.push("acknowledged_at = NULL");
  }
  if (status === "closed") {
    values.push(Number(actorUserId) || null);
    updateParts.push(`closed_by_user_id = $${values.length}`);
    updateParts.push("closed_at = NOW()");
  }

  const r = await q(
    `UPDATE merchant_payroll_batch
     SET ${updateParts.join(", ")}
     WHERE id = $1
       AND merchant_id = $2
     RETURNING *`,
    values
  );
  return r.rows[0] || null;
}

export async function listMerchantAccountantUsers(merchantId) {
  const r = await q(
    `SELECT DISTINCT u.id
     FROM merchant_accountant ma
     JOIN app_user u ON u.id = ma.accountant_user_id
     WHERE ma.merchant_id = $1
       AND ma.is_active = TRUE
       AND u.is_account_disabled = FALSE`,
    [Number(merchantId)]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
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
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function withTransaction(work) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const out = await work(client);
    await client.query("COMMIT");
    return out;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function findPayrollItemById(itemId) {
  const r = await q(
    `SELECT *
     FROM merchant_payroll_item
     WHERE id = $1
     LIMIT 1`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}

export async function markPayrollBatchAcknowledged({
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
     RETURNING *`,
    [Number(batchId), Number(merchantId), Number(accountantUserId)]
  );
  return r.rows[0] || null;
}

export async function markPayrollItemPaid({
  itemId,
  accountantUserId,
  payoutNote,
}) {
  const r = await q(
    `UPDATE merchant_payroll_item
     SET
       status = 'paid',
       paid_by_user_id = $2,
       paid_at = NOW(),
       payout_note = COALESCE($3, payout_note),
       updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(itemId), Number(accountantUserId), payoutNote || null]
  );
  return r.rows[0] || null;
}

export async function listLeaveRequests({
  merchantId,
  employeeUserId = null,
  dateFrom = null,
  dateTo = null,
  status = null,
  limit = 120,
}) {
  const safeLimit = clampLimit(limit, 120);
  const params = [Number(merchantId)];
  const clauses = ["lr.merchant_id = $1"];

  if (employeeUserId != null) {
    params.push(Number(employeeUserId));
    clauses.push(`lr.employee_user_id = $${params.length}`);
  }
  if (dateFrom) {
    params.push(toNullableDate(dateFrom));
    clauses.push(`lr.date_to >= $${params.length}`);
  }
  if (dateTo) {
    params.push(toNullableDate(dateTo));
    clauses.push(`lr.date_from <= $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    clauses.push(`lr.status = $${params.length}`);
  }

  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       lr.*,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone,
       requester.full_name AS requested_by_full_name,
       decider.full_name AS decided_by_full_name
     FROM merchant_leave_request lr
     JOIN app_user u ON u.id = lr.employee_user_id
     LEFT JOIN app_user requester ON requester.id = lr.requested_by_user_id
     LEFT JOIN app_user decider ON decider.id = lr.decided_by_user_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY lr.created_at DESC, lr.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function createLeaveRequest({
  merchantId,
  employeeUserId,
  leaveType,
  payPolicy,
  dateFrom,
  dateTo,
  daysCount,
  reason,
  requestedByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_leave_request
      (
        merchant_id,
        employee_user_id,
        leave_type,
        pay_policy,
        date_from,
        date_to,
        days_count,
        reason,
        status,
        requested_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'pending',$9,NOW(),NOW())
     RETURNING *`,
    [
      Number(merchantId),
      Number(employeeUserId),
      String(leaveType || "annual").slice(0, 24),
      String(payPolicy || "paid").slice(0, 24),
      toNullableDate(dateFrom),
      toNullableDate(dateTo),
      Number(daysCount || 1),
      reason ? String(reason).slice(0, 3000) : null,
      Number(requestedByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function findLeaveRequestById({ merchantId, leaveId }) {
  const r = await q(
    `SELECT *
     FROM merchant_leave_request
     WHERE id = $1
       AND merchant_id = $2
     LIMIT 1`,
    [Number(leaveId), Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function decideLeaveRequest({
  merchantId,
  leaveId,
  status,
  decisionNote,
  decidedByUserId,
}) {
  const r = await q(
    `UPDATE merchant_leave_request
     SET
       status = $3,
       decision_note = COALESCE($4, decision_note),
       decided_by_user_id = $5,
       decided_at = NOW(),
       updated_at = NOW()
     WHERE id = $1
       AND merchant_id = $2
     RETURNING *`,
    [
      Number(leaveId),
      Number(merchantId),
      String(status),
      decisionNote ? String(decisionNote).slice(0, 3000) : null,
      Number(decidedByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listApprovedLeaveByPeriod({
  merchantId,
  periodYear,
  periodMonth,
}) {
  const bounds = monthBounds(periodYear, periodMonth);
  if (!bounds) return [];
  const r = await q(
    `SELECT *
     FROM merchant_leave_request
     WHERE merchant_id = $1
       AND status = 'approved'
       AND date_to >= $2
       AND date_from <= $3
     ORDER BY employee_user_id ASC, date_from ASC, id ASC`,
    [Number(merchantId), bounds.from, bounds.to]
  );
  return r.rows;
}

export async function listSalaryActions({
  merchantId,
  employeeUserId = null,
  periodYear = null,
  periodMonth = null,
  status = null,
  limit = 200,
}) {
  const safeLimit = clampLimit(limit, 200);
  const params = [Number(merchantId)];
  const clauses = ["sa.merchant_id = $1"];
  if (employeeUserId != null) {
    params.push(Number(employeeUserId));
    clauses.push(`sa.employee_user_id = $${params.length}`);
  }
  if (periodYear != null) {
    params.push(Number(periodYear));
    clauses.push(`sa.effective_year = $${params.length}`);
  }
  if (periodMonth != null) {
    params.push(Number(periodMonth));
    clauses.push(`sa.effective_month = $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    clauses.push(`sa.status = $${params.length}`);
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       sa.*,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone,
       creator.full_name AS created_by_full_name
     FROM merchant_salary_action sa
     JOIN app_user u ON u.id = sa.employee_user_id
     LEFT JOIN app_user creator ON creator.id = sa.created_by_user_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY sa.effective_year DESC, sa.effective_month DESC, sa.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function createSalaryAction({
  merchantId,
  employeeUserId,
  actionType,
  amount,
  currency,
  effectiveYear,
  effectiveMonth,
  description,
  createdByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_salary_action
      (
        merchant_id,
        employee_user_id,
        action_type,
        amount,
        currency,
        effective_year,
        effective_month,
        description,
        status,
        created_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'active',$9,NOW(),NOW())
     RETURNING *`,
    [
      Number(merchantId),
      Number(employeeUserId),
      String(actionType || "bonus").slice(0, 24),
      Number(amount || 0),
      String(currency || "IQD").slice(0, 10),
      Number(effectiveYear),
      Number(effectiveMonth),
      description ? String(description).slice(0, 3000) : null,
      Number(createdByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function updateSalaryActionStatus({
  merchantId,
  actionId,
  status,
}) {
  const r = await q(
    `UPDATE merchant_salary_action
     SET status = $3,
         updated_at = NOW()
     WHERE id = $1
       AND merchant_id = $2
     RETURNING *`,
    [Number(actionId), Number(merchantId), String(status)]
  );
  return r.rows[0] || null;
}

export async function listSalaryActionsByPeriod({
  merchantId,
  periodYear,
  periodMonth,
}) {
  const r = await q(
    `SELECT *
     FROM merchant_salary_action
     WHERE merchant_id = $1
       AND effective_year = $2
       AND effective_month = $3
       AND status IN ('active', 'applied')
     ORDER BY id ASC`,
    [Number(merchantId), Number(periodYear), Number(periodMonth)]
  );
  return r.rows;
}

export async function markSalaryActionsApplied({
  merchantId,
  actionIds,
  batchId,
}) {
  if (!Array.isArray(actionIds) || actionIds.length === 0) {
    return [];
  }
  const ids = actionIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return [];
  const r = await q(
    `UPDATE merchant_salary_action
     SET status = 'applied',
         applied_batch_id = $3,
         updated_at = NOW()
     WHERE merchant_id = $1
       AND id = ANY($2::bigint[])
     RETURNING *`,
    [Number(merchantId), ids, Number(batchId)]
  );
  return r.rows;
}

export async function getAttendanceMonthlyArchive({
  merchantId,
  periodYear,
  periodMonth,
}) {
  const bounds = monthBounds(periodYear, periodMonth);
  if (!bounds) {
    return [];
  }
  const r = await q(
    `SELECT
       al.employee_user_id,
       u.full_name AS employee_full_name,
       COUNT(*)::int AS total_days,
       COALESCE(SUM(CASE WHEN al.status IN ('present', 'late', 'half_day') THEN 1 ELSE 0 END), 0)::int AS present_days,
       COALESCE(SUM(CASE WHEN al.status = 'absent' THEN 1 ELSE 0 END), 0)::int AS absent_days,
       COALESCE(SUM(CASE WHEN al.status = 'leave' THEN 1 ELSE 0 END), 0)::int AS leave_days
     FROM merchant_attendance_log al
     JOIN app_user u ON u.id = al.employee_user_id
     WHERE al.merchant_id = $1
       AND al.attendance_date BETWEEN $2 AND $3
     GROUP BY al.employee_user_id, u.full_name
     ORDER BY u.full_name ASC`,
    [Number(merchantId), bounds.from, bounds.to]
  );
  return r.rows;
}

export async function listAdvanceRequests({
  merchantId,
  employeeUserId = null,
  status = null,
  limit = 120,
}) {
  const safeLimit = clampLimit(limit, 120);
  const params = [Number(merchantId)];
  const clauses = ["ar.merchant_id = $1"];
  if (employeeUserId != null) {
    params.push(Number(employeeUserId));
    clauses.push(`ar.employee_user_id = $${params.length}`);
  }
  if (status) {
    params.push(String(status));
    clauses.push(`ar.status = $${params.length}`);
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       ar.*,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone,
       requester.full_name AS requested_by_full_name,
       decider.full_name AS decided_by_full_name
     FROM merchant_advance_request ar
     JOIN app_user u ON u.id = ar.employee_user_id
     LEFT JOIN app_user requester ON requester.id = ar.requested_by_user_id
     LEFT JOIN app_user decider ON decider.id = ar.decided_by_user_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY ar.created_at DESC, ar.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function createAdvanceRequest({
  merchantId,
  employeeUserId,
  requestedAmount,
  currency,
  reason,
  requestedByUserId,
}) {
  const r = await q(
    `INSERT INTO merchant_advance_request
      (
        merchant_id,
        employee_user_id,
        requested_amount,
        currency,
        reason,
        status,
        requested_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,'pending',$6,NOW(),NOW())
     RETURNING *`,
    [
      Number(merchantId),
      Number(employeeUserId),
      Number(requestedAmount || 0),
      String(currency || "IQD").slice(0, 10),
      reason ? String(reason).slice(0, 3000) : null,
      Number(requestedByUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function findAdvanceRequestById({ merchantId, requestId }) {
  const r = await q(
    `SELECT *
     FROM merchant_advance_request
     WHERE merchant_id = $1
       AND id = $2
     LIMIT 1`,
    [Number(merchantId), Number(requestId)]
  );
  return r.rows[0] || null;
}

export async function rejectAdvanceRequest({
  merchantId,
  requestId,
  decidedByUserId,
  decisionNote,
}) {
  const r = await q(
    `UPDATE merchant_advance_request
     SET status = 'rejected',
         decided_by_user_id = $3,
         decided_at = NOW(),
         decision_note = COALESCE($4, decision_note),
         updated_at = NOW()
     WHERE merchant_id = $1
       AND id = $2
     RETURNING *`,
    [
      Number(merchantId),
      Number(requestId),
      Number(decidedByUserId) || null,
      decisionNote ? String(decisionNote).slice(0, 3000) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function approveAdvanceRequest({
  merchantId,
  requestId,
  decidedByUserId,
  decisionNote,
  effectiveYear,
  effectiveMonth,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const found = await client.query(
      `SELECT *
       FROM merchant_advance_request
       WHERE merchant_id = $1
         AND id = $2
       FOR UPDATE`,
      [Number(merchantId), Number(requestId)]
    );
    const request = found.rows[0] || null;
    if (!request) {
      await client.query("ROLLBACK");
      return null;
    }
    if (String(request.status) !== "pending") {
      await client.query("ROLLBACK");
      return { request, salaryAction: null };
    }

    const createdAction = await client.query(
      `INSERT INTO merchant_salary_action
        (
          merchant_id,
          employee_user_id,
          action_type,
          amount,
          currency,
          effective_year,
          effective_month,
          description,
          status,
          created_by_user_id,
          created_at,
          updated_at
        )
       VALUES ($1,$2,'advance',$3,$4,$5,$6,$7,'active',$8,NOW(),NOW())
       RETURNING *`,
      [
        Number(merchantId),
        Number(request.employee_user_id),
        Number(request.requested_amount || 0),
        String(request.currency || "IQD").slice(0, 10),
        Number(effectiveYear),
        Number(effectiveMonth),
        decisionNote
          ? String(decisionNote).slice(0, 3000)
          : request.reason
          ? String(request.reason).slice(0, 3000)
          : null,
        Number(decidedByUserId) || null,
      ]
    );
    const salaryAction = createdAction.rows[0] || null;

    const updatedRequest = await client.query(
      `UPDATE merchant_advance_request
       SET status = 'approved',
           decided_by_user_id = $3,
           decided_at = NOW(),
           decision_note = COALESCE($4, decision_note),
           linked_salary_action_id = $5,
           updated_at = NOW()
       WHERE merchant_id = $1
         AND id = $2
       RETURNING *`,
      [
        Number(merchantId),
        Number(requestId),
        Number(decidedByUserId) || null,
        decisionNote ? String(decisionNote).slice(0, 3000) : null,
        salaryAction?.id ? Number(salaryAction.id) : null,
      ]
    );

    await client.query("COMMIT");
    return {
      request: updatedRequest.rows[0] || request,
      salaryAction,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
