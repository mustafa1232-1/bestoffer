/**
 * Purpose:
 * تقييم الموظفين (المرحلة 5). المقاييس محسوبة من التذاكر (support_ticket) والحضور
 * (company_attendance) — لا تُخزَّن مكررة. لا تعتمد على عدد التذاكر وحده: تشمل
 * الجودة (تقييم المستخدم) وSLA ووقت الاستجابة/الحل.
 */

import { q } from "../../config/db.js";

export async function computeTicketMetrics({ agentUserId, from = null, to = null }) {
  const params = [Number(agentUserId)];
  let dateFilter = "";
  if (from) {
    params.push(from);
    dateFilter += ` AND created_at >= $${params.length}`;
  }
  if (to) {
    params.push(to);
    dateFilter += ` AND created_at <= $${params.length}`;
  }
  const r = await q(
    `SELECT
       COUNT(*)::int AS received,
       COUNT(*) FILTER (WHERE status IN ('RESOLVED','CLOSED'))::int AS resolved,
       COUNT(*) FILTER (WHERE status NOT IN ('RESOLVED','CLOSED'))::int AS open,
       COALESCE(SUM(reopened_count), 0)::int AS reopened,
       AVG(EXTRACT(EPOCH FROM (first_response_at - created_at)))
         FILTER (WHERE first_response_at IS NOT NULL) AS avg_first_response_secs,
       AVG(EXTRACT(EPOCH FROM (resolved_at - created_at)))
         FILTER (WHERE resolved_at IS NOT NULL) AS avg_resolution_secs,
       COUNT(*) FILTER (
         WHERE (first_response_at IS NOT NULL AND sla_first_response_due_at IS NOT NULL
                AND first_response_at > sla_first_response_due_at)
            OR (resolved_at IS NOT NULL AND sla_resolution_due_at IS NOT NULL
                AND resolved_at > sla_resolution_due_at)
       )::int AS sla_breaches,
       AVG(rating) FILTER (WHERE rating IS NOT NULL) AS avg_rating,
       COUNT(*) FILTER (WHERE rating IS NOT NULL)::int AS rated_count
     FROM support_ticket
     WHERE assigned_user_id = $1 ${dateFilter}`,
    params
  );
  const row = r.rows[0] || {};
  const received = Number(row.received || 0);
  const slaBreaches = Number(row.sla_breaches || 0);
  return {
    received,
    resolved: Number(row.resolved || 0),
    open: Number(row.open || 0),
    reopened: Number(row.reopened || 0),
    avgFirstResponseSecs: row.avg_first_response_secs != null ? Math.round(Number(row.avg_first_response_secs)) : null,
    avgResolutionSecs: row.avg_resolution_secs != null ? Math.round(Number(row.avg_resolution_secs)) : null,
    slaBreaches,
    slaBreachRate: received > 0 ? Number((slaBreaches / received).toFixed(3)) : 0,
    avgRating: row.avg_rating != null ? Number(Number(row.avg_rating).toFixed(2)) : null,
    ratedCount: Number(row.rated_count || 0),
  };
}

export async function computeAttendanceMetrics({ employeeUserId, from = null, to = null }) {
  const params = [Number(employeeUserId)];
  let dateFilter = "";
  if (from) {
    params.push(from);
    dateFilter += ` AND check_in_at >= $${params.length}`;
  }
  if (to) {
    params.push(to);
    dateFilter += ` AND check_in_at <= $${params.length}`;
  }
  const r = await q(
    `SELECT
       COUNT(DISTINCT (check_in_at AT TIME ZONE 'Asia/Baghdad')::date)::int AS days_present,
       COALESCE(SUM(
         EXTRACT(EPOCH FROM (COALESCE(check_out_at, NOW()) - check_in_at))
       ), 0)::bigint AS total_secs
     FROM company_attendance
     WHERE employee_user_id = $1 ${dateFilter}`,
    params
  );
  const row = r.rows[0] || {};
  return {
    daysPresent: Number(row.days_present || 0),
    totalHours: Number((Number(row.total_secs || 0) / 3600).toFixed(1)),
  };
}

export async function listAgentsWithTickets({ from = null, to = null, limit = 100 }) {
  const params = [];
  let dateFilter = "";
  if (from) {
    params.push(from);
    dateFilter += ` AND created_at >= $${params.length}`;
  }
  if (to) {
    params.push(to);
    dateFilter += ` AND created_at <= $${params.length}`;
  }
  params.push(Math.max(1, Math.min(500, Number(limit) || 100)));
  const r = await q(
    `SELECT t.assigned_user_id AS user_id, u.full_name
     FROM support_ticket t
     JOIN app_user u ON u.id = t.assigned_user_id
     WHERE t.assigned_user_id IS NOT NULL ${dateFilter}
     GROUP BY t.assigned_user_id, u.full_name
     ORDER BY COUNT(*) DESC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function upsertReview({
  employeeUserId, period, supervisorRating = null, supervisorNote = null, reviewedByUserId,
}) {
  const r = await q(
    `INSERT INTO company_employee_review
       (employee_user_id, period, supervisor_rating, supervisor_note, reviewed_by_user_id)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (employee_user_id, period) DO UPDATE SET
       supervisor_rating = EXCLUDED.supervisor_rating,
       supervisor_note = EXCLUDED.supervisor_note,
       reviewed_by_user_id = EXCLUDED.reviewed_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [Number(employeeUserId), String(period), supervisorRating, supervisorNote, reviewedByUserId ? Number(reviewedByUserId) : null]
  );
  return r.rows[0];
}

export async function addObjection({ employeeUserId, period, objectionText }) {
  const r = await q(
    `UPDATE company_employee_review
     SET objection_text = $3, objection_at = NOW(), updated_at = NOW()
     WHERE employee_user_id = $1 AND period = $2
     RETURNING *`,
    [Number(employeeUserId), String(period), objectionText]
  );
  if (!r.rows[0]) return { code: "REVIEW_NOT_FOUND" };
  return { code: "OK", review: r.rows[0] };
}

export async function getReview({ employeeUserId, period }) {
  const r = await q(
    `SELECT * FROM company_employee_review WHERE employee_user_id = $1 AND period = $2`,
    [Number(employeeUserId), String(period)]
  );
  return r.rows[0] || null;
}
