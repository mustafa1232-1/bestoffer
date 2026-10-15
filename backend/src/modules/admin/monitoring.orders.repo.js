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
import { pool } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { directAssignDeliveryOrderTx } from "../commerce/commerce.repo.js";

const MONITORING_ORDER_ASSIGNABLE_STATUSES = new Set([
  "approved",
  "preparing",
  "ready_for_delivery",
  "ready_for_pickup",
  "picked_up",
  "on_the_way",
  "arrived",
]);

function addOrderMonitoringStatusFilter({ conds, params, status }) {
  const normalized = String(status || "").trim().toLowerCase();
  if (!normalized) return;

  const pushArray = (values) => {
    params.push(values);
    return `$${params.length}`;
  };
  const pushValue = (value) => {
    params.push(value);
    return `$${params.length}`;
  };

  switch (normalized) {
    case "approved":
    case "accepted_by_store": {
      const placeholder = pushArray(["approved", "accepted_by_store"]);
      conds.push(`o.status::text = ANY(${placeholder}::text[])`);
      return;
    }
    case "courier_requested":
    case "pending_no_driver":
    case "needs_delivery": {
      const terminalPlaceholder = pushArray(ORDER_TERMINAL_STATUSES);
      conds.push(
        `(o.delivery_assignment_status = 'PENDING_NO_DRIVER'
          AND o.status::text <> ALL(${terminalPlaceholder}::text[]))`
      );
      return;
    }
    case "courier_assigned": {
      const terminalPlaceholder = pushArray(ORDER_TERMINAL_STATUSES);
      conds.push(
        `(o.delivery_assignment_status = 'ASSIGNED'
          AND o.status::text <> ALL(${terminalPlaceholder}::text[]))`
      );
      return;
    }
    case "completed": {
      const placeholder = pushArray(ORDER_COMPLETED_STATUSES);
      conds.push(`o.status::text = ANY(${placeholder}::text[])`);
      return;
    }
    case "cancelled": {
      const placeholder = pushArray(ORDER_CANCELLED_STATUSES);
      conds.push(`o.status::text = ANY(${placeholder}::text[])`);
      return;
    }
    default: {
      const placeholder = pushValue(normalized);
      conds.push(`o.status::text = ${placeholder}`);
    }
  }
}

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
  const attention = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE status::text = ANY($1)
            OR delivery_assignment_status = 'PENDING_NO_DRIVER'
            OR (
              status::text = ANY($2)
              AND updated_at < NOW() - INTERVAL '45 minutes'
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE status::text = ANY($2)
           AND updated_at < NOW() - INTERVAL '45 minutes'
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_type IN ('order','customer_order')
             AND st.entity_id::text = customer_order.id::text
             AND st.status = ANY($3)
         )
       )::int AS open_tickets
     FROM customer_order`,
    [ORDER_NEEDS_DELIVERY_STATUSES, ORDER_ACTIVE_STATUSES, SUPPORT_OPEN_STATUSES]
  );
  const row = r.rows[0] || {};
  const attentionRow = attention.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(attentionRow.delayed || 0),
    needsAttention: Number(attentionRow.needs_attention || 0),
    openTickets: Number(attentionRow.open_tickets || 0),
  };
}

export async function listOrdersForMonitoring({
  status = null,
  search = "",
  from = null,
  to = null,
  merchantId = null,
  userId = null,
  deliveryUserId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  addOrderMonitoringStatusFilter({ conds, params, status });
  if (merchantId) {
    params.push(Number(merchantId));
    conds.push(`o.merchant_id = $${params.length}`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`o.customer_user_id = $${params.length}`);
  }
  if (deliveryUserId) {
    params.push(Number(deliveryUserId));
    conds.push(`o.delivery_user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(o.id::text ILIKE $${params.length}
        OR o.customer_full_name ILIKE $${params.length}
        OR COALESCE(o.customer_phone, '') ILIKE $${params.length}
        OR COALESCE(m.name, '') ILIKE $${params.length}
        OR COALESCE(du.full_name, '') ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "o.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "o.created_at ASC, o.id ASC"
      : sort === "created_desc"
        ? "o.created_at DESC, o.id DESC"
        : "o.updated_at DESC, o.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       o.id,
       o.status::text AS status,
       o.delivery_assignment_status,
       o.customer_user_id,
       o.customer_full_name,
       o.merchant_id,
       m.name AS merchant_name,
       o.delivery_user_id,
       du.full_name AS delivery_name,
       o.subtotal,
       o.delivery_fee,
       o.service_fee,
       o.total_amount,
       o.courier_source,
       o.courier_requested_at,
       o.courier_assigned_at,
       o.prepared_at,
       o.ready_for_pickup_at,
       o.picked_up_at,
       o.delivered_at,
       o.completed_at,
       o.cancelled_at,
       o.cancellation_reason,
       o.created_at,
       o.updated_at,
       COUNT(oi.id)::int AS item_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_type IN ('order','customer_order')
           AND st.entity_id::text = o.id::text
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket,
       EXISTS (
         SELECT 1 FROM order_revision rev
         WHERE rev.order_id = o.id
           AND rev.status NOT IN ('applied','cancelled','rejected')
       ) AS has_open_revision
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     LEFT JOIN order_item oi ON oi.order_id = o.id
     ${where}
     GROUP BY o.id, m.name, du.full_name
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

export async function getOrderMonitoringDetail(orderId, { includePhone = false } = {}) {
  const id = Number(orderId);
  if (!Number.isFinite(id) || id <= 0) return null;

  const orderRes = await q(
    `SELECT
       o.*,
       m.name AS merchant_name,
       m.phone AS merchant_phone,
       du.full_name AS delivery_name,
       du.phone AS delivery_phone
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     WHERE o.id = $1
     LIMIT 1`,
    [id]
  );
  const order = orderRes.rows[0] || null;
  if (!order) return null;

  if (!includePhone) {
    order.customer_phone = null;
    order.merchant_phone = null;
    order.delivery_phone = null;
  }

  const items = await q(
    `SELECT
       oi.*,
       p.name AS product_name,
       p.image_url AS product_image_url
     FROM order_item oi
     LEFT JOIN product p ON p.id = oi.product_id
     WHERE oi.order_id = $1
     ORDER BY oi.id ASC`,
    [id]
  );

  const jobs = await q(
    `SELECT *
     FROM delivery_job
     WHERE primary_order_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 20`,
    [id]
  ).catch(() => ({ rows: [] }));

  const assignments = await q(
    `SELECT ca.*
     FROM courier_assignment ca
     WHERE ca.order_id = $1
        OR ca.delivery_job_id IN (
          SELECT id FROM delivery_job WHERE primary_order_id = $1
        )
     ORDER BY ca.requested_at DESC, ca.id DESC
     LIMIT 50`,
    [id]
  ).catch(() => ({ rows: [] }));

  const tickets = await q(
    `SELECT id, status, priority, subject, created_at, updated_at
     FROM support_ticket
     WHERE entity_id::text = $1::text
       AND (entity_type IN ('order','customer_order') OR domain = 'ORDERS')
     ORDER BY created_at DESC, id DESC
     LIMIT 50`,
    [id]
  ).catch(() => ({ rows: [] }));

  return {
    order,
    items: items.rows,
    deliveryJobs: jobs.rows,
    courierAssignments: assignments.rows,
    tickets: tickets.rows,
  };
}

function previousDriverFromOrder(order) {
  const id = Number(order?.delivery_user_id || 0);
  if (!Number.isFinite(id) || id <= 0) return null;
  return {
    id,
    full_name: order.delivery_name || null,
    phone: order.delivery_phone || null,
  };
}

function assertMonitoringOrderAssignable(order) {
  const status = String(order?.status || "").trim().toLowerCase();
  if (!MONITORING_ORDER_ASSIGNABLE_STATUSES.has(status)) {
    throw new AppError("ORDER_ASSIGNMENT_NOT_ALLOWED", { status: 409 });
  }
}

async function getCourierActiveOrderCountTx(client, courierUserId, { exceptOrderId = null } = {}) {
  const r = await client.query(
    `SELECT COUNT(*)::int AS count
     FROM customer_order o
     WHERE o.delivery_user_id = $1
       AND o.delivery_assignment_status = 'ASSIGNED'
       AND ($2::bigint IS NULL OR o.id <> $2)`,
    [
      Number(courierUserId),
      exceptOrderId == null ? null : Number(exceptOrderId),
    ],
  );
  return Number(r.rows[0]?.count || 0);
}

async function notifyMonitoringCourierChange({
  order,
  previousDriver = null,
  newDriver = null,
  activeOrderCountBefore = 0,
  removed = false,
  changedBy = "monitoring",
}) {
  const notifications = [];
  const orderId = Number(order.id);
  const merchantId = Number(order.merchant_id);
  const merchantName = order.merchant_name || "المتجر";

  if (previousDriver?.id && (!newDriver?.id || Number(previousDriver.id) !== Number(newDriver.id))) {
    notifications.push({
      userId: Number(previousDriver.id),
      type: "delivery_order_removed",
      title: "تمت إزالة طلب من جدولك",
      body: `تمت إزالة الطلب #${orderId} من جدولك بواسطة متابعة الطلبات.`,
      orderId,
      merchantId,
      payload: {
        orderId,
        target: "courier_orders_current",
        targetModule: "courier",
        target_module: "courier",
        action: "refresh_orders",
        roleScope: "courier",
        role_scope: "courier",
        targetEntity: "order",
        target_entity: "order",
        entityId: orderId,
        entity_id: orderId,
        changedBy,
        requiresAction: true,
      },
    });
  }

  if (newDriver?.id) {
    const additional = Number(activeOrderCountBefore || 0) > 0;
    notifications.push({
      userId: Number(newDriver.id),
      type: "delivery_order_assigned",
      title: additional ? "تم إسناد طلب إضافي لك" : "تم إسناد طلب لك",
      body: additional
        ? `تم إسناد طلب إضافي #${orderId} من ${merchantName} لك.`
        : `تم إسناد الطلب #${orderId} من ${merchantName} لك.`,
      orderId,
      merchantId,
      payload: {
        orderId,
        target: "courier_orders_current",
        targetModule: "courier",
        target_module: "courier",
        action: "open_assigned_order",
        roleScope: "courier",
        role_scope: "courier",
        targetEntity: "order",
        target_entity: "order",
        entityId: orderId,
        entity_id: orderId,
        assignmentStatus: "ASSIGNED",
        additionalOrder: additional,
        changedBy,
      },
    });
  }

  if (order.owner_user_id) {
    notifications.push({
      userId: Number(order.owner_user_id),
      type: removed ? "owner_delivery_removed" : "owner_delivery_assigned",
      title: removed ? "تمت إزالة الدلفري" : "تم تعيين الدلفري",
      body: removed
        ? `تمت إزالة الدلفري من الطلب #${orderId}.`
        : `تم تعيين دلفري للطلب #${orderId}.`,
      orderId,
      merchantId,
      payload: {
        orderId,
        target: "owner_orders",
        action: "open_owner_order",
        roleScope: "owner",
        assignmentStatus: removed ? "PENDING_NO_DRIVER" : "ASSIGNED",
        changedBy,
      },
    });
  }

  if (order.customer_user_id) {
    notifications.push({
      userId: Number(order.customer_user_id),
      type: removed ? "customer_delivery_pending" : "customer_delivery_assigned",
      title: removed ? "بانتظار دلفري متاح" : "تم تعيين التوصيل",
      body: removed
        ? `الطلب #${orderId} بانتظار دلفري متاح.`
        : `تم تعيين دلفري للطلب #${orderId}.`,
      orderId,
      merchantId,
      payload: {
        orderId,
        target: "order_tracking",
        action: "open_order_tracking",
        assignmentStatus: removed ? "PENDING_NO_DRIVER" : "ASSIGNED",
        changedBy,
      },
    });
  }

  if (notifications.length > 0) {
    await createManyNotifications(notifications);
  }
}

export async function assignOrderCourierForMonitoring({
  actorUserId = null,
  orderId,
  courierUserId = null,
  allowBusyCourier = false,
  note = null,
} = {}) {
  const id = Number(orderId);
  if (!Number.isFinite(id) || id <= 0) {
    throw new AppError("ORDER_NOT_FOUND", { status: 404 });
  }

  const nextCourierId =
    courierUserId == null || courierUserId === ""
      ? null
      : Number(courierUserId);
  if (
    courierUserId != null &&
    courierUserId !== "" &&
    (!Number.isFinite(nextCourierId) || nextCourierId <= 0)
  ) {
    throw new AppError("COURIER_NOT_FOUND", { status: 404 });
  }

  const client = await pool.connect();
  let notificationContext = null;
  try {
    await client.query("BEGIN");

    const currentResult = await client.query(
      `SELECT
         o.id,
         o.merchant_id,
         o.status,
         o.customer_user_id,
         o.customer_block,
         o.delivery_user_id,
         o.delivery_assignment_status,
         m.name AS merchant_name,
         m.owner_user_id,
         du.full_name AS delivery_name,
         du.phone AS delivery_phone
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       LEFT JOIN app_user du ON du.id = o.delivery_user_id
       WHERE o.id = $1
       FOR UPDATE OF o`,
      [id],
    );
    const current = currentResult.rows[0] || null;
    if (!current) throw new AppError("ORDER_NOT_FOUND", { status: 404 });
    assertMonitoringOrderAssignable(current);

    const previousDriver = previousDriverFromOrder(current);

    if (nextCourierId == null) {
      await client.query(
        `UPDATE courier_assignment
         SET ended_at = COALESCE(ended_at, NOW()),
             ended_reason = COALESCE(ended_reason, 'MONITORING_REMOVED'),
             responded_at = COALESCE(responded_at, NOW()),
             status = CASE
               WHEN status IN ('pending', 'assigned', 'accepted') THEN 'released'
               ELSE status
             END
         WHERE order_id = $1
           AND ended_at IS NULL`,
        [id],
      );

      const pendingResult = await client.query(
        `UPDATE customer_order
         SET delivery_user_id = NULL,
             delivery_assignment_status = 'PENDING_NO_DRIVER',
             assigned_by_store = FALSE,
             courier_source = 'app',
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [id],
      );
      const pendingOrder = pendingResult.rows[0] || current;

      await client.query("COMMIT");
      notificationContext = {
        order: { ...current, ...pendingOrder },
        previousDriver,
        removed: true,
      };
      return {
        order: pendingOrder,
        assignmentStatus: "PENDING_NO_DRIVER",
        driver: null,
        previousDriver,
        removed: true,
      };
    }

    const activeOrderCountBefore = await getCourierActiveOrderCountTx(
      client,
      nextCourierId,
      { exceptOrderId: id },
    );

    const assignmentResult = await directAssignDeliveryOrderTx(client, {
      orderId: id,
      merchantId: Number(current.merchant_id),
      requestedByUserId: actorUserId == null ? null : Number(actorUserId),
      customerBlock: current.customer_block || null,
      assignmentType: "monitoring_manual",
      explicitCourierUserId: nextCourierId,
      allowPending: false,
      allowBusyCourier: Boolean(allowBusyCourier),
      allowStalePresenceCourier: true,
      replaceExistingAssignment: true,
      changedByRole: "admin",
      assignedByStore: false,
      note,
    });

    await client.query("COMMIT");
    notificationContext = {
      order: { ...current, ...assignmentResult.order },
      previousDriver: assignmentResult.previousDriver || previousDriver,
      newDriver: assignmentResult.driver || null,
      activeOrderCountBefore,
      removed: false,
    };
    return {
      order: assignmentResult.order,
      assignment: assignmentResult.assignment || null,
      assignmentStatus: assignmentResult.assignmentStatus,
      driver: assignmentResult.driver || null,
      previousDriver: assignmentResult.previousDriver || previousDriver,
      activeOrderCountBefore,
      assigned: assignmentResult.assignmentCreated,
    };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
    if (notificationContext) {
      try {
        await notifyMonitoringCourierChange(notificationContext);
      } catch (notifyError) {
        console.error("[monitoring-orders] courier change notify failed", {
          orderId: Number(orderId),
          error: notifyError?.message || String(notifyError),
        });
      }
    }
  }
}

export const __monitoringOrdersRepoTestables = {
  addOrderMonitoringStatusFilter,
};
