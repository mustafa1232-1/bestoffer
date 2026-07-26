import {
  q,
  ORDER_TERMINAL_STATUSES,
  ORDER_COMPLETED_STATUSES,
  ORDER_CANCELLED_STATUSES,
  ORDER_ACTIVE_STATUSES,
  ORDER_NEEDS_DELIVERY_STATUSES,
  DELIVERY_JOB_TERMINAL_STATUSES,
  SUPPORT_OPEN_STATUSES,
  SERVICE_ACTIVE_STATUSES,
  SERVICE_COMPLETED_STATUSES,
  SERVICE_CANCELLED_STATUSES,
  MARKETPLACE_ACTIVE_STATUSES,
  REAL_ESTATE_DONE_STATUSES,
  MARKETPLACE_CANCELLED_STATUSES,
  JOB_ACTIVE_STATUSES,
  JOB_CLOSED_STATUSES,
  JOB_ATTENTION_STATUSES,
  INTERNAL_COMMUNITY_ROLES,
  safeLimitOffset,
  addDateFilters,
} from "./monitoring.shared.js";

export async function getJobMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE jp.status = ANY($1)
           AND jp.deleted_at IS NULL
           AND (jp.expires_at IS NULL OR jp.expires_at >= NOW())
       )::int AS active,
       COUNT(*) FILTER (
         WHERE jp.status = ANY($2)
           AND (jp.updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE jp.deleted_at IS NOT NULL
           AND (jp.deleted_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today,
       COUNT(*) FILTER (
         WHERE jp.status = 'active'
           AND jp.expires_at IS NOT NULL
           AND jp.expires_at < NOW()
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE jp.status = ANY($3)
            OR EXISTS (
              SELECT 1 FROM support_ticket st
              WHERE st.entity_id = jp.id
                AND (
                  st.domain = 'JOBS'
                  OR st.entity_type IN ('job_post','job')
                )
                AND st.status = ANY($4)
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = jp.id
             AND (
               st.domain = 'JOBS'
               OR st.entity_type IN ('job_post','job')
             )
             AND st.status = ANY($4)
         )
       )::int AS open_tickets
     FROM job_post jp`,
    [
      JOB_ACTIVE_STATUSES,
      JOB_CLOSED_STATUSES,
      JOB_ATTENTION_STATUSES,
      SUPPORT_OPEN_STATUSES,
    ]
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(row.delayed || 0),
    needsAttention: Number(row.needs_attention || 0),
    openTickets: Number(row.open_tickets || 0),
  };
}

export async function listJobsForMonitoring({
  status = null,
  search = "",
  region = null,
  from = null,
  to = null,
  userId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    params.push(String(status));
    conds.push(`jp.status = $${params.length}`);
  }
  if (region) {
    params.push(String(region));
    conds.push(`(jp.city = $${params.length} OR jp.area = $${params.length})`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`jp.created_by_user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(jp.id::text ILIKE $${params.length}
        OR jp.title ILIKE $${params.length}
        OR jp.company_name ILIKE $${params.length}
        OR jp.category ILIKE $${params.length}
        OR jp.city ILIKE $${params.length}
        OR COALESCE(jp.area, '') ILIKE $${params.length}
        OR u.full_name ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "jp.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "jp.created_at ASC, jp.id ASC"
      : sort === "expires_asc"
        ? "jp.expires_at ASC NULLS LAST, jp.updated_at DESC"
        : sort === "applications_desc"
          ? "application_count DESC, jp.updated_at DESC"
          : "jp.updated_at DESC, jp.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM job_post jp
     JOIN app_user u ON u.id = jp.created_by_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       jp.id,
       jp.title,
       jp.company_name,
       jp.category,
       jp.city,
       jp.area,
       jp.workplace_type,
       jp.employment_type,
       jp.experience_level,
       jp.status,
       jp.vacancies,
       jp.is_featured,
       jp.published_at,
       jp.expires_at,
       jp.created_by_user_id,
       u.full_name AS publisher_name,
       jp.created_at,
       jp.updated_at,
       COUNT(ja.id)::int AS application_count,
       COUNT(ja.id) FILTER (WHERE ja.status = 'submitted')::int AS submitted_count,
       COUNT(ja.id) FILTER (WHERE ja.resume_url IS NOT NULL AND ja.resume_url <> '')::int AS resume_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_id = jp.id
           AND (
             st.domain = 'JOBS'
             OR st.entity_type IN ('job_post','job')
           )
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket
     FROM job_post jp
     JOIN app_user u ON u.id = jp.created_by_user_id
     LEFT JOIN job_application ja ON ja.job_id = jp.id
     ${where}
     GROUP BY jp.id, u.full_name
     ORDER BY ${orderBy}
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    [...params, SUPPORT_OPEN_STATUSES]
  );

  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: page.limit,
    offset: page.offset,
    items: rows.rows,
  };
}

export async function getJobMonitoringDetail(jobId) {
  const id = Number(jobId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const jobRes = await q(
    `SELECT jp.*, u.full_name AS publisher_name
     FROM job_post jp
     JOIN app_user u ON u.id = jp.created_by_user_id
     WHERE jp.id = $1
     LIMIT 1`,
    [id]
  );
  const job = jobRes.rows[0] || null;
  if (!job) return null;
  const stats = await q(
    `SELECT
       COUNT(*)::int AS total,
       COUNT(*) FILTER (WHERE status = 'submitted')::int AS submitted,
       COUNT(*) FILTER (WHERE status = 'shortlisted')::int AS shortlisted,
       COUNT(*) FILTER (WHERE status = 'rejected')::int AS rejected,
       COUNT(*) FILTER (WHERE status = 'hired')::int AS hired,
       COUNT(*) FILTER (WHERE resume_url IS NOT NULL AND resume_url <> '')::int AS with_cv
     FROM job_application
     WHERE job_id = $1`,
    [id]
  );
  return { job, applicationStats: stats.rows[0] || {} };
}

export async function listJobApplicationsForMonitoring({
  jobId,
  status = null,
  limit = 25,
  offset = 0,
} = {}) {
  const id = Number(jobId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const page = safeLimitOffset({ limit, offset });
  const params = [id];
  const conds = ["ja.job_id = $1"];
  if (status) {
    params.push(String(status));
    conds.push(`ja.status = $${params.length}`);
  }
  const where = `WHERE ${conds.join(" AND ")}`;
  const countRes = await q(
    `SELECT COUNT(*)::int AS total FROM job_application ja ${where}`,
    params
  );
  params.push(page.limit, page.offset);
  const rows = await q(
    `SELECT
       ja.id,
       ja.job_id,
       ja.applicant_user_id,
       ja.full_name,
       ja.phone,
       ja.message,
       ja.expected_salary,
       ja.status,
       ja.created_at,
       ja.updated_at,
       (ja.resume_url IS NOT NULL AND ja.resume_url <> '') AS has_cv
     FROM job_application ja
     ${where}
     ORDER BY ja.created_at DESC, ja.id DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: page.limit,
    offset: page.offset,
    items: rows.rows,
  };
}

export async function getJobApplicationMonitoringDetail(applicationId) {
  const id = Number(applicationId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const r = await q(
    `SELECT
       ja.id,
       ja.job_id,
       jp.title AS job_title,
       ja.applicant_user_id,
       ja.full_name,
       ja.phone,
       ja.message,
       ja.expected_salary,
       ja.status,
       ja.created_at,
       ja.updated_at,
       (ja.resume_url IS NOT NULL AND ja.resume_url <> '') AS has_cv
     FROM job_application ja
     JOIN job_post jp ON jp.id = ja.job_id
     WHERE ja.id = $1
     LIMIT 1`,
    [id]
  );
  return r.rows[0] || null;
}

export async function getJobApplicationCvForMonitoring(applicationId) {
  const id = Number(applicationId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const r = await q(
    `SELECT id, job_id, full_name, resume_url
     FROM job_application
     WHERE id = $1
     LIMIT 1`,
    [id]
  );
  const row = r.rows[0] || null;
  if (!row || !row.resume_url) return row ? { ...row, resume_url: null } : null;
  return row;
}
