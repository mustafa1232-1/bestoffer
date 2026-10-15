import { pool } from "../config/db.js";
import { isOwnerCurrentStatus } from "../modules/orders/order-flow.logic.js";

const orderId = Number(process.env.ORDER_ID || process.argv[2] || 0);

function usage() {
  console.error("Usage: node src/scripts/diagnoseOrderVisibility.js <orderId>");
}

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase();
}

function ownerTabFor(row) {
  const status = normalizeStatus(row?.status);
  if (isOwnerCurrentStatus(status, row?.customer_confirmed_at)) {
    if (status === "pending") return "current:new";
    if (status === "approved") return "current:approved";
    if (status === "preparing") return "current:preparing";
    if (status === "ready_for_delivery" || status === "ready_for_pickup") {
      return "current:ready";
    }
    if (status === "on_the_way" || status === "arrived") {
      return "current:delivering";
    }
    return "current";
  }
  if (
    ["cancelled", "cancelled_by_customer", "cancelled_by_store", "cancelled_by_admin"].includes(
      status,
    )
  ) {
    return "cancelled";
  }
  return "history";
}

async function main() {
  if (!Number.isFinite(orderId) || orderId <= 0) {
    usage();
    process.exitCode = 2;
    return;
  }

  const orderResult = await pool.query(
    `SELECT
       o.id,
       o.merchant_id,
       m.name AS merchant_name,
       m.owner_user_id,
       owner.username AS owner_username,
       owner.phone AS owner_phone,
       o.status::text AS status,
       o.delivery_type,
       o.delivery_assignment_status,
       o.delivery_user_id,
       courier.full_name AS delivery_full_name,
       o.customer_full_name,
       o.customer_phone,
       o.customer_block,
       o.customer_building_number,
       o.customer_apartment,
       o.subtotal,
       o.delivery_fee,
       o.total_amount,
       o.customer_confirmed_at,
       to_char(o.created_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS created_baghdad,
       to_char(o.approved_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS approved_baghdad,
       to_char(o.courier_requested_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS courier_requested_baghdad,
       to_char(o.courier_assigned_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS courier_assigned_baghdad,
       to_char(o.updated_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS updated_baghdad
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user owner ON owner.id = m.owner_user_id
     LEFT JOIN app_user courier ON courier.id = o.delivery_user_id
     WHERE o.id = $1`,
    [orderId],
  );

  const order = orderResult.rows[0] || null;
  if (!order) {
    console.log(JSON.stringify({ orderId, found: false }, null, 2));
    return;
  }

  const visibleCurrentResult = await pool.query(
    `SELECT COUNT(*)::int AS count
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
      WHERE o.id = $1
        AND m.owner_user_id = $2
        AND o.status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')`,
    [orderId, Number(order.owner_user_id)],
  );

  const items = await pool.query(
    `SELECT
       oi.id,
       oi.product_id,
       oi.product_name,
       oi.quantity,
       oi.unit_price,
       (COALESCE(oi.quantity, 0) * COALESCE(oi.unit_price, 0))::numeric AS line_total,
       p.merchant_id AS product_merchant_id,
       p.is_available
     FROM order_item oi
     LEFT JOIN product p ON p.id = oi.product_id
     WHERE oi.order_id = $1
     ORDER BY oi.id`,
    [orderId],
  );

  const history = await pool.query(
    `SELECT
       old_status,
       new_status,
       lifecycle_old,
       lifecycle_new,
       changed_by_user_id,
       note,
       to_char(created_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS created_baghdad
     FROM order_status_history
     WHERE order_id = $1
     ORDER BY created_at`,
    [orderId],
  );

  const assignments = await pool.query(
    `SELECT
       ca.id,
       ca.courier_user_id,
       courier.full_name AS courier_name,
       ca.assignment_type,
       ca.status,
       ca.ended_reason,
       to_char(ca.created_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS created_baghdad,
       to_char(ca.responded_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS responded_baghdad,
       to_char(ca.ended_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS ended_baghdad
     FROM courier_assignment ca
     LEFT JOIN app_user courier ON courier.id = ca.courier_user_id
     WHERE ca.order_id = $1
     ORDER BY ca.id`,
    [orderId],
  );

  const output = {
    orderId,
    found: true,
    ownerVisible: {
      currentEndpointCandidate:
        Number(visibleCurrentResult.rows[0]?.count || 0) > 0 &&
        isOwnerCurrentStatus(order.status, order.customer_confirmed_at),
      expectedOwnerTab: ownerTabFor(order),
    },
    order,
    items: items.rows,
    assignments: assignments.rows,
    history: history.rows,
  };

  console.log(JSON.stringify(output, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
