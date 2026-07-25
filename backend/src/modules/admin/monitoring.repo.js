/**
 * Purpose:
 * تجميعات لوحة المتابعة الموحدة (المرحلة 3) التي لا تخص وحدة التاكسي.
 * عدّادات الطلبات تُقرأ مباشرة من customer_order (قراءة تجميعية للـbackoffice).
 * التوقيت المحلي: Asia/Baghdad.
 */

import { q } from "../../config/db.js";

const ORDER_TERMINAL_STATUSES = [
  "delivered",
  "completed",
  "received_by_customer",
  "cancelled",
  "cancelled_by_admin",
  "cancelled_by_customer",
  "cancelled_by_store",
  "expired",
  "failed_delivery",
];

const ORDER_COMPLETED_STATUSES = ["completed", "delivered", "received_by_customer"];
const ORDER_CANCELLED_STATUSES = [
  "cancelled",
  "cancelled_by_admin",
  "cancelled_by_customer",
  "cancelled_by_store",
  "expired",
  "failed_delivery",
];

export async function getOrderMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status::text <> ALL($1))::int AS active,
       COUNT(*) FILTER (
         WHERE status::text = ANY($2)
           AND (updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE status::text = ANY($3)
           AND (updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today
     FROM customer_order`,
    [ORDER_TERMINAL_STATUSES, ORDER_COMPLETED_STATUSES, ORDER_CANCELLED_STATUSES]
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
  };
}
