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

export async function getTicketMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status = ANY($1))::int AS active,
       COUNT(*) FILTER (
         WHERE status IN ('RESOLVED','CLOSED')
           AND (COALESCE(resolved_at, closed_at, updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       0::int AS cancelled_today,
       COUNT(*) FILTER (
         WHERE status = ANY($1)
           AND (
             (first_response_at IS NULL AND sla_first_response_due_at < NOW())
             OR (resolved_at IS NULL AND sla_resolution_due_at < NOW())
           )
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE status = ANY($1)
           AND (
             assigned_user_id IS NULL
             OR priority = 'urgent'
             OR (
               first_response_at IS NULL
               AND sla_first_response_due_at < NOW() + INTERVAL '30 minutes'
             )
             OR (
               resolved_at IS NULL
               AND sla_resolution_due_at < NOW() + INTERVAL '30 minutes'
             )
           )
       )::int AS needs_attention,
       COUNT(*) FILTER (WHERE status = ANY($1))::int AS open_tickets
     FROM support_ticket`,
    [SUPPORT_OPEN_STATUSES]
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

export async function getOpsAlertMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'open')::int AS active,
       COUNT(*) FILTER (
         WHERE status IN ('resolved','ignored')
           AND (COALESCE(resolved_at, updated_at) AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE status = 'ignored'
           AND (COALESCE(resolved_at, updated_at) AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today,
       COUNT(*) FILTER (
         WHERE status = 'open'
           AND created_at < NOW() - INTERVAL '30 minutes'
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE status = 'open'
           AND severity IN ('high','critical')
       )::int AS needs_attention,
       COUNT(*) FILTER (WHERE status = 'acknowledged')::int AS acknowledged
     FROM ops_alert`
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(row.delayed || 0),
    needsAttention: Number(row.needs_attention || 0),
    acknowledged: Number(row.acknowledged || 0),
  };
}
