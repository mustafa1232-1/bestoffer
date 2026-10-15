import { pool } from "../config/db.js";
import { createManyNotifications } from "../modules/notifications/notifications.repo.js";

const CONFIRM_TOKEN = "CANCEL_ORDER_EVERYWHERE";
const CANCELLED_STATUSES = new Set([
  "cancelled",
  "cancelled_by_customer",
  "cancelled_by_store",
  "cancelled_by_admin",
]);
const COMPLETED_STATUSES = new Set([
  "delivered",
  "delivered_by_courier",
  "received_by_customer",
  "completed",
]);

function parseArgs(argv) {
  const args = argv.slice(2);
  const out = {
    orderId: Number(args.find((arg) => /^\d+$/.test(arg)) || 0),
    execute: args.includes("--execute"),
    includeGroup: args.includes("--include-group"),
    confirm: "",
    reason: "admin_cancel_order_everywhere",
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--confirm") out.confirm = String(args[index + 1] || "");
    if (arg === "--reason") out.reason = String(args[index + 1] || "").trim();
  }
  return out;
}

function usage() {
  console.error(
    [
      "Usage:",
      `  node src/scripts/cancelOrderEverywhere.js <orderId>`,
      `  node src/scripts/cancelOrderEverywhere.js <orderId> --execute --confirm ${CONFIRM_TOKEN}`,
      "",
      "Options:",
      "  --include-group   cancel every child order in the same order_group_id",
      "  --reason <text>   store an audit reason",
    ].join("\n"),
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms) || 0)));
}

function isTerminal(status) {
  const normalized = String(status || "").trim().toLowerCase();
  return CANCELLED_STATUSES.has(normalized) || COMPLETED_STATUSES.has(normalized);
}

function lifecycleFromStatus(status) {
  switch (String(status || "").trim().toLowerCase()) {
    case "pending":
      return "PENDING";
    case "approved":
      return "ACCEPTED_BY_STORE";
    case "preparing":
      return "PREPARING";
    case "ready_for_delivery":
    case "ready_for_pickup":
      return "READY_FOR_PICKUP";
    case "on_the_way":
      return "ON_THE_WAY";
    case "arrived":
      return "ARRIVED";
    case "delivered":
    case "delivered_by_courier":
      return "DELIVERED_BY_COURIER";
    case "completed":
    case "received_by_customer":
      return "COMPLETED";
    case "cancelled_by_customer":
      return "CANCELLED_BY_CUSTOMER";
    case "cancelled_by_admin":
      return "CANCELLED_BY_ADMIN";
    case "cancelled":
    case "cancelled_by_store":
      return "CANCELLED_BY_STORE";
    default:
      return "PENDING";
  }
}

function groupStatusFrom(statuses) {
  const normalized = statuses.map((status) =>
    String(status || "").trim().toLowerCase(),
  );
  if (normalized.length <= 0) return "pending";
  if (normalized.every((status) => CANCELLED_STATUSES.has(status))) {
    return "cancelled";
  }
  if (normalized.every((status) => COMPLETED_STATUSES.has(status))) {
    return "completed";
  }
  if (normalized.some((status) => status === "ready_for_delivery")) {
    return "ready_for_delivery";
  }
  if (normalized.some((status) => status === "preparing")) return "preparing";
  if (normalized.some((status) => status === "approved")) return "approved";
  if (normalized.some((status) => status === "pending")) return "pending";
  return normalized[0] || "pending";
}

async function releaseReservationsTx(client, orderId) {
  const rows = await client.query(
    `SELECT *
       FROM inventory_reservation
      WHERE order_id = $1
        AND status = ANY($2::varchar[])
      ORDER BY id ASC
      FOR UPDATE`,
    [Number(orderId), ["pending", "consumed"]],
  );

  for (const reservation of rows.rows) {
    if (reservation.variant_id != null) {
      await client.query(
        `UPDATE product_variant
            SET stock_quantity = stock_quantity + $2,
                updated_at = NOW()
          WHERE id = $1`,
        [Number(reservation.variant_id), Number(reservation.quantity || 0)],
      );
    } else if (reservation.variant_signature) {
      await client.query(
        `UPDATE product_variant
            SET stock_quantity = stock_quantity + $3,
                updated_at = NOW()
          WHERE product_id = $1
            AND signature = $2`,
        [
          Number(reservation.product_id),
          reservation.variant_signature,
          Number(reservation.quantity || 0),
        ],
      );
    } else if (reservation.merchant_id != null && reservation.product_id != null) {
      await client.query(
        `UPDATE store_inventory_item
            SET quantity = quantity + $3,
                stock_status = CASE
                  WHEN quantity + $3 <= COALESCE(reorder_threshold, 0) THEN 'low_stock'
                  ELSE 'in_stock'
                END,
                auto_disabled = FALSE,
                last_quantity_update_at = NOW(),
                updated_at = NOW()
          WHERE merchant_id = $1
            AND product_id = $2`,
        [
          Number(reservation.merchant_id),
          Number(reservation.product_id),
          Number(reservation.quantity || 0),
        ],
      );
    }

    await client.query(
      `UPDATE inventory_reservation
          SET status = 'released',
              released_at = COALESCE(released_at, NOW()),
              updated_at = NOW()
        WHERE id = $1`,
      [Number(reservation.id)],
    );
  }

  return rows.rows.length;
}

async function closeCourierAssignmentsTx(client, orderId, reason) {
  const result = await client.query(
    `UPDATE courier_assignment
        SET ended_at = COALESCE(ended_at, NOW()),
            ended_reason = COALESCE(ended_reason, $2),
            cancelled_at = COALESCE(cancelled_at, NOW()),
            responded_at = COALESCE(responded_at, NOW()),
            status = CASE
              WHEN status IN ('pending', 'assigned', 'accepted') THEN 'cancelled'
              ELSE status
            END
      WHERE order_id = $1
        AND ended_at IS NULL
      RETURNING id, courier_user_id`,
    [Number(orderId), reason],
  );
  return result.rows;
}

async function syncGroupTx(client, orderGroupId) {
  if (!orderGroupId) return null;
  const rows = await client.query(
    `SELECT id, status, subtotal, delivery_fee, delivery_fee_raw, total_amount
       FROM customer_order
      WHERE order_group_id = $1
      ORDER BY store_sequence ASC, id ASC`,
    [Number(orderGroupId)],
  );
  if (rows.rowCount <= 0) return null;

  const nextStatus = groupStatusFrom(rows.rows.map((row) => row.status));
  await client.query(
    `UPDATE order_group
        SET status = $2,
            updated_at = NOW()
      WHERE id = $1`,
    [Number(orderGroupId), nextStatus],
  );
  for (const row of rows.rows) {
    await client.query(
      `UPDATE order_group_item_summary
          SET status = $3,
              subtotal = $4,
              delivery_fee = $5,
              raw_delivery_fee = $6,
              total_amount = $7,
              updated_at = NOW()
        WHERE order_group_id = $1
          AND child_order_id = $2`,
      [
        Number(orderGroupId),
        Number(row.id),
        String(row.status || ""),
        Number(row.subtotal || 0),
        Number(row.delivery_fee || 0),
        Number(row.delivery_fee_raw || row.delivery_fee || 0),
        Number(row.total_amount || 0),
      ],
    );
  }
  return nextStatus;
}

function notificationRowsFor(order, previousCourierIds) {
  const orderId = Number(order.id);
  const merchantId = Number(order.merchant_id);
  const payload = {
    targetEntity: "order",
    target_entity: "order",
    entityId: orderId,
    entity_id: orderId,
    orderId,
    merchantId,
    status: "cancelled_by_admin",
    action: "open_cancelled_order",
    notificationType: "admin_cancel_order_everywhere",
    notification_type: "admin_cancel_order_everywhere",
  };
  const rows = [];
  if (Number(order.owner_user_id || 0) > 0) {
    rows.push({
      userId: Number(order.owner_user_id),
      type: "owner_order_cancelled_by_admin",
      title: "Order cancelled",
      body: `Order #${orderId} has been cancelled by support.`,
      orderId,
      merchantId,
      payload: { ...payload, target: "owner_orders", roleScope: "owner" },
    });
  }
  if (Number(order.customer_user_id || 0) > 0) {
    rows.push({
      userId: Number(order.customer_user_id),
      type: "customer_order_cancelled",
      title: "Order cancelled",
      body: `Order #${orderId} has been cancelled.`,
      orderId,
      merchantId,
      payload: { ...payload, target: "order_tracking", roleScope: "user" },
    });
  }
  for (const courierId of previousCourierIds) {
    if (Number(courierId || 0) <= 0) continue;
    rows.push({
      userId: Number(courierId),
      type: "courier_order_cancelled",
      title: "Order cancelled",
      body: `Order #${orderId} has been cancelled.`,
      orderId,
      merchantId,
      payload: {
        ...payload,
        target: "courier_orders_current",
        roleScope: "courier",
      },
    });
  }
  return rows;
}

async function main() {
  const args = parseArgs(process.argv);
  if (!Number.isFinite(args.orderId) || args.orderId <= 0) {
    usage();
    process.exitCode = 2;
    return;
  }

  const client = await pool.connect();
  const notifications = [];
  try {
    await client.query("BEGIN");
    const targetResult = await client.query(
      `SELECT o.*, m.name AS merchant_name, m.owner_user_id
         FROM customer_order o
         JOIN merchant m ON m.id = o.merchant_id
        WHERE o.id = $1
        FOR UPDATE OF o`,
      [args.orderId],
    );
    const target = targetResult.rows[0] || null;
    if (!target) {
      await client.query("ROLLBACK");
      console.log(JSON.stringify({ orderId: args.orderId, found: false }, null, 2));
      return;
    }

    const orderIds =
      args.includeGroup && target.order_group_id != null
        ? (
            await client.query(
              `SELECT id
                 FROM customer_order
                WHERE order_group_id = $1
                ORDER BY store_sequence ASC, id ASC
                FOR UPDATE`,
              [Number(target.order_group_id)],
            )
          ).rows.map((row) => Number(row.id))
        : [Number(target.id)];

    const before = await client.query(
      `SELECT o.id,
              o.merchant_id,
              m.name AS merchant_name,
              o.status,
              o.delivery_assignment_status,
              o.delivery_user_id,
              o.order_group_id,
              to_char(o.created_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS created_baghdad
         FROM customer_order o
         JOIN merchant m ON m.id = o.merchant_id
        WHERE o.id = ANY($1::bigint[])
        ORDER BY o.id`,
      [orderIds],
    );

    if (!args.execute) {
      await client.query("ROLLBACK");
      console.log(
        JSON.stringify(
          {
            execute: false,
            confirmationRequired: `--execute --confirm ${CONFIRM_TOKEN}`,
            includeGroup: args.includeGroup,
            orders: before.rows,
          },
          null,
          2,
        ),
      );
      return;
    }

    if (args.confirm !== CONFIRM_TOKEN) {
      await client.query("ROLLBACK");
      console.error(`Refusing to execute without --confirm ${CONFIRM_TOKEN}`);
      process.exitCode = 2;
      return;
    }

    const results = [];
    for (const id of orderIds) {
      const rowResult = await client.query(
        `SELECT o.*, m.name AS merchant_name, m.owner_user_id
           FROM customer_order o
           JOIN merchant m ON m.id = o.merchant_id
          WHERE o.id = $1
          FOR UPDATE OF o`,
        [Number(id)],
      );
      const order = rowResult.rows[0];
      if (!order) continue;

      const previousCourierIds = new Set();
      if (Number(order.delivery_user_id || 0) > 0) {
        previousCourierIds.add(Number(order.delivery_user_id));
      }
      const openAssignments = await client.query(
        `SELECT courier_user_id
           FROM courier_assignment
          WHERE order_id = $1
            AND ended_at IS NULL`,
        [Number(id)],
      );
      for (const assignment of openAssignments.rows) {
        if (Number(assignment.courier_user_id || 0) > 0) {
          previousCourierIds.add(Number(assignment.courier_user_id));
        }
      }

      const releasedReservations = await releaseReservationsTx(client, id);
      const closedAssignments = await closeCourierAssignmentsTx(
        client,
        id,
        "ORDER_CANCELLED_BY_ADMIN",
      );

      let updated = order;
      if (!isTerminal(order.status)) {
        const updateResult = await client.query(
          `UPDATE customer_order
              SET status = 'cancelled_by_admin'::order_status,
                  delivery_assignment_status = 'CANCELLED',
                  delivery_user_id = NULL,
                  cancelled_at = COALESCE(cancelled_at, NOW()),
                  cancelled_by_role = 'admin',
                  cancellation_reason = COALESCE(cancellation_reason, $2),
                  cancellation_reason_code = COALESCE(cancellation_reason_code, 'admin_cancel_order_everywhere'),
                  cancellation_reason_text = COALESCE(cancellation_reason_text, $2),
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [Number(id), args.reason],
        );
        updated = { ...order, ...updateResult.rows[0] };
        await client.query(
          `INSERT INTO order_status_history
             (order_id, old_status, new_status, lifecycle_old, lifecycle_new, changed_by_user_id, changed_by_role, note)
           VALUES ($1,$2::order_status,'cancelled_by_admin'::order_status,$3,'CANCELLED_BY_ADMIN',NULL,'admin',$4)`,
          [
            Number(id),
            String(order.status || "pending"),
            lifecycleFromStatus(order.status),
            args.reason,
          ],
        );
      } else {
        await client.query(
          `UPDATE customer_order
              SET delivery_assignment_status = 'CANCELLED',
                  delivery_user_id = NULL,
                  updated_at = NOW()
            WHERE id = $1
              AND (
                delivery_assignment_status IS DISTINCT FROM 'CANCELLED'
                OR delivery_user_id IS NOT NULL
              )`,
          [Number(id)],
        );
      }

      await client.query(
        `INSERT INTO order_action_event
           (order_id, actor_user_id, actor_scope, action_kind, reason_code, reason_text, metadata_json)
         VALUES ($1,NULL,'admin','cancel','admin_cancel_order_everywhere',$2,$3::jsonb)`,
        [
          Number(id),
          args.reason,
          JSON.stringify({
            source: "cancelOrderEverywhere",
            includeGroup: args.includeGroup,
          }),
        ],
      );

      notifications.push(
        ...notificationRowsFor(updated, [...previousCourierIds]),
      );
      results.push({
        orderId: Number(id),
        previousStatus: String(order.status || ""),
        nextStatus: isTerminal(order.status)
          ? String(order.status || "")
          : "cancelled_by_admin",
        previousDeliveryAssignmentStatus:
          order.delivery_assignment_status || null,
        nextDeliveryAssignmentStatus: "CANCELLED",
        previousDeliveryUserId: order.delivery_user_id
          ? Number(order.delivery_user_id)
          : null,
        releasedReservations,
        closedAssignmentIds: closedAssignments.map((row) => Number(row.id)),
        notifiedUserIds: [
          Number(order.owner_user_id || 0),
          Number(order.customer_user_id || 0),
          ...[...previousCourierIds],
        ].filter((value) => Number.isFinite(value) && value > 0),
      });
    }

    const groupStatus = await syncGroupTx(client, target.order_group_id);
    await client.query("COMMIT");

    const createdNotifications = await createManyNotifications(notifications);
    if (createdNotifications.length > 0) {
      await sleep(750);
    }
    const after = await pool.query(
      `SELECT o.id,
              o.merchant_id,
              m.name AS merchant_name,
              o.status,
              o.delivery_assignment_status,
              o.delivery_user_id,
              o.order_group_id,
              to_char(o.updated_at AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD HH24:MI:SS') AS updated_baghdad
         FROM customer_order o
         JOIN merchant m ON m.id = o.merchant_id
        WHERE o.id = ANY($1::bigint[])
        ORDER BY o.id`,
      [orderIds],
    );

    console.log(
      JSON.stringify(
        {
          execute: true,
          includeGroup: args.includeGroup,
          groupStatus,
          before: before.rows,
          results,
          after: after.rows,
          notificationsCreated: createdNotifications.length,
        },
        null,
        2,
      ),
    );
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    console.error(error);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
