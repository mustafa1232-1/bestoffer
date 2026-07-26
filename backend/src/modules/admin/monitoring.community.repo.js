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

export async function getCommunityMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE u.role::text <> ALL($1)
       )::int AS active,
       (
         SELECT COUNT(*)::int
         FROM social_post p
         WHERE p.is_deleted = FALSE
           AND p.moderation_status = 'approved'
           AND (p.created_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       ) AS completed_today,
       (
         SELECT COUNT(*)::int
         FROM social_post p
         WHERE p.is_deleted = TRUE
           AND (p.updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       ) AS cancelled_today,
       0::int AS delayed,
       COUNT(*) FILTER (
         WHERE COALESCE(u.social_violation_strikes, 0) > 0
            OR COALESCE(u.social_visibility_tier, 'normal') <> 'normal'
            OR EXISTS (
              SELECT 1 FROM social_user_report sur
              WHERE sur.reported_user_id = u.id
            )
            OR EXISTS (
              SELECT 1 FROM social_capability_restriction scr
              WHERE scr.user_id = u.id
                AND scr.revoked_at IS NULL
                AND (scr.ends_at IS NULL OR scr.ends_at > NOW())
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = u.id
             AND (
               st.domain = 'COMMUNITY'
               OR st.entity_type IN ('community_user','social_user','user')
             )
             AND st.status = ANY($2)
         )
       )::int AS open_tickets
     FROM app_user u`,
    [INTERNAL_COMMUNITY_ROLES, SUPPORT_OPEN_STATUSES]
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

export async function listCommunityUsersForMonitoring({
  status = null,
  search = "",
  from = null,
  to = null,
  userId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [`u.role::text <> ALL($1)`];
  const params = [INTERNAL_COMMUNITY_ROLES];

  if (status === "reported") {
    conds.push(`EXISTS (SELECT 1 FROM social_user_report sur WHERE sur.reported_user_id = u.id)`);
  } else if (status === "restricted") {
    conds.push(
      `EXISTS (
        SELECT 1 FROM social_capability_restriction scr
        WHERE scr.user_id = u.id
          AND scr.revoked_at IS NULL
          AND (scr.ends_at IS NULL OR scr.ends_at > NOW())
      )`
    );
  } else if (status) {
    params.push(String(status));
    conds.push(`u.social_visibility_tier = $${params.length}`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`u.id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(u.id::text ILIKE $${params.length}
        OR u.full_name ILIKE $${params.length}
        OR COALESCE(u.username, '') ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "u.created_at" });
  const where = `WHERE ${conds.join(" AND ")}`;
  const orderBy =
    sort === "created_asc"
      ? "u.created_at ASC, u.id ASC"
      : sort === "reports_desc"
        ? "report_count DESC, u.updated_at DESC"
        : "u.updated_at DESC, u.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM app_user u
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       u.id,
       u.full_name,
       u.username,
       u.role::text AS role,
       u.created_at,
       u.updated_at,
       COALESCE(u.social_violation_strikes, 0)::int AS social_violation_strikes,
       COALESCE(u.social_visibility_tier, 'normal') AS social_visibility_tier,
       COUNT(DISTINCT sp.id) FILTER (WHERE sp.post_kind NOT IN ('reel','merchant_review'))::int AS post_count,
       COUNT(DISTINCT sp.id) FILTER (WHERE sp.post_kind = 'image')::int AS photo_count,
       COUNT(DISTINCT sp.id) FILTER (WHERE sp.post_kind = 'reel')::int AS reel_count,
       COUNT(DISTINCT ss.id)::int AS story_count,
       COUNT(DISTINCT pc.id)::int AS comment_count,
       COUNT(DISTINCT sur.id)::int AS report_count,
       COUNT(DISTINCT scr.id) FILTER (
         WHERE scr.revoked_at IS NULL
           AND (scr.ends_at IS NULL OR scr.ends_at > NOW())
       )::int AS active_restriction_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_id = u.id
           AND (
             st.domain = 'COMMUNITY'
             OR st.entity_type IN ('community_user','social_user','user')
           )
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket
     FROM app_user u
     LEFT JOIN social_post sp ON sp.user_id = u.id AND sp.is_deleted = FALSE
     LEFT JOIN social_story ss ON ss.user_id = u.id AND ss.is_deleted = FALSE
     LEFT JOIN social_post_comment pc ON pc.user_id = u.id AND pc.is_deleted = FALSE
     LEFT JOIN social_user_report sur ON sur.reported_user_id = u.id
     LEFT JOIN social_capability_restriction scr ON scr.user_id = u.id
     ${where}
     GROUP BY u.id
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
