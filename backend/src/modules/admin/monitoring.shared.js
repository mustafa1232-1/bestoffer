/**
 * Purpose:
 * تجميعات لوحة المتابعة الموحدة (المرحلة 3) التي لا تخص وحدة التاكسي.
 * عدّادات الطلبات تُقرأ مباشرة من customer_order (قراءة تجميعية للـbackoffice).
 * التوقيت المحلي: Asia/Baghdad.
 */

import { q } from "../../config/db.js";

export { q };

export const ORDER_TERMINAL_STATUSES = [
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

export const ORDER_COMPLETED_STATUSES = ["completed", "delivered", "received_by_customer"];
export const ORDER_CANCELLED_STATUSES = [
  "cancelled",
  "cancelled_by_admin",
  "cancelled_by_customer",
  "cancelled_by_store",
  "expired",
  "failed_delivery",
];

export const ORDER_ACTIVE_STATUSES = [
  "pending",
  "approved",
  "accepted_by_store",
  "preparing",
  "ready_for_delivery",
  "courier_requested",
  "courier_assigned",
  "on_the_way",
  "picked_up",
  "arrived",
];

export const ORDER_NEEDS_DELIVERY_STATUSES = [
  "ready_for_delivery",
  "courier_requested",
];

export const DELIVERY_JOB_TERMINAL_STATUSES = ["COMPLETED", "CANCELLED", "FAILED"];
export const SUPPORT_OPEN_STATUSES = [
  "new",
  "NEW",
  "TRIAGED",
  "ASSIGNED",
  "assigned",
  "IN_PROGRESS",
  "in_progress",
  "WAITING_FOR_CUSTOMER",
  "WAITING_FOR_MERCHANT",
  "WAITING_FOR_CAPTAIN",
  "WAITING_FOR_DELIVERY",
  "waiting_customer",
  "waiting_internal",
  "ESCALATED",
  "escalated",
  "REOPENED",
  "reopened",
];

export const SERVICE_ACTIVE_STATUSES = [
  "pending",
  "awaiting_provider",
  "accepted",
  "scheduled",
  "in_progress",
  "PENDING_PROVIDER_CONFIRMATION",
  "CONFIRMED",
  "IN_PROGRESS",
  "PROVIDER_COMPLETED",
  "DISPUTED",
];
export const SERVICE_COMPLETED_STATUSES = ["completed", "COMPLETED"];
export const SERVICE_CANCELLED_STATUSES = [
  "cancelled",
  "rejected",
  "REJECTED_BY_PROVIDER",
  "CANCELLED_BY_CUSTOMER",
  "CANCELLED_BY_PROVIDER",
  "CANCELLED_BY_ADMIN",
  "EXPIRED",
];
export const MARKETPLACE_ACTIVE_STATUSES = ["active"];
export const REAL_ESTATE_DONE_STATUSES = ["sold", "rented"];
export const MARKETPLACE_CANCELLED_STATUSES = [
  "archived",
  "hidden_due_subscription_expiry",
];
export const JOB_ACTIVE_STATUSES = ["active"];
export const JOB_CLOSED_STATUSES = ["closed"];
export const JOB_ATTENTION_STATUSES = ["draft", "paused"];
export const INTERNAL_COMMUNITY_ROLES = [
  "admin",
  "deputy_admin",
  "call_center",
  "accountant",
  "hr",
  "company_portal",
];

export function safeLimitOffset({ limit = 25, offset = 0 } = {}) {
  return {
    limit: Math.max(1, Math.min(100, Number(limit) || 25)),
    offset: Math.max(0, Number(offset) || 0),
  };
}

export function addDateFilters({ conds, params, from, to, column = "created_at" }) {
  if (from) {
    params.push(from);
    conds.push(`${column} >= $${params.length}`);
  }
  if (to) {
    params.push(to);
    conds.push(`${column} <= $${params.length}`);
  }
}
