import { pool } from "../config/db.js";

const merchantId = Number(process.env.MERCHANT_ID || process.argv[2] || 52);

async function main() {
  const merchants = await pool.query(
    `SELECT id, name, owner_user_id, phone, type, is_open
       FROM merchant
      WHERE id = $1
      ORDER BY id`,
    [merchantId]
  );

  const orders = await pool.query(
    `SELECT co.id,
            co.merchant_id,
            m.name AS merchant_name,
            co.status,
            co.delivery_type,
            co.is_merchant_delivery,
            co.delivery_assignment_status,
            co.delivery_user_id,
            co.created_at,
            co.approved_at,
            co.courier_requested_at,
            co.courier_assigned_at,
            co.updated_at
       FROM customer_order co
       JOIN merchant m ON m.id = co.merchant_id
      WHERE co.merchant_id = $1
      ORDER BY co.id DESC
      LIMIT 25`,
    [merchantId]
  );

  const assignments = await pool.query(
    `SELECT ca.id,
            ca.order_id,
            ca.courier_user_id,
            ca.assignment_type,
            ca.status,
            ca.created_at,
            ca.responded_at,
            ca.ended_at,
            ca.ended_reason
       FROM courier_assignment ca
       JOIN customer_order co ON co.id = ca.order_id
      WHERE co.merchant_id = $1
      ORDER BY ca.id DESC
      LIMIT 40`,
    [merchantId]
  );

  const drivers = await pool.query(
    `SELECT u.id AS user_id,
            u.role,
            cp.active_status,
            cp.availability_status,
            COALESCE(cp.driver_type, 'app') AS driver_type,
            p.is_online,
            p.updated_at AS presence_updated_at,
            ROUND(EXTRACT(EPOCH FROM NOW() - p.updated_at))::INT AS presence_age_sec,
            (
              SELECT COUNT(*)::INT
                FROM courier_assignment ca
               WHERE ca.courier_user_id = u.id
                 AND ca.ended_at IS NULL
                 AND ca.status IN ('assigned', 'accepted', 'picked_up', 'on_the_way', 'arrived')
            ) AS open_assignments
       FROM app_user u
       LEFT JOIN courier_profile cp ON cp.user_id = u.id
       LEFT JOIN courier_presence p ON p.courier_user_id = u.id
      WHERE u.role = 'delivery'
        AND COALESCE(cp.active_status, TRUE) = TRUE
      ORDER BY p.updated_at DESC NULLS LAST
      LIMIT 25`
  );

  const pendingNoDriver = await pool.query(
    `SELECT co.id,
            co.merchant_id,
            m.name AS merchant_name,
            co.status,
            co.delivery_assignment_status,
            co.delivery_user_id,
            co.created_at,
            co.courier_requested_at
       FROM customer_order co
       JOIN merchant m ON m.id = co.merchant_id
      WHERE co.delivery_assignment_status = 'PENDING_NO_DRIVER'
        AND co.status IN ('approved', 'preparing', 'ready_for_delivery')
      ORDER BY co.created_at DESC
      LIMIT 50`
  );

  const orderIds = orders.rows.map((row) => Number(row.id)).filter(Boolean);
  const history = orderIds.length
    ? await pool.query(
        `SELECT order_id, old_status, new_status, lifecycle_old, lifecycle_new, changed_by_user_id, note, created_at
           FROM order_status_history
          WHERE order_id = ANY($1::bigint[])
          ORDER BY order_id DESC, created_at ASC`,
        [orderIds]
      )
    : { rows: [] };
  const items = orderIds.length
    ? await pool.query(
        `SELECT oi.order_id,
                oi.id AS order_item_id,
                oi.product_id,
                oi.product_name AS ordered_product_name,
                p.name AS current_product_name,
                p.is_available,
                p.merchant_id AS product_merchant_id,
                oi.quantity
           FROM order_item oi
           LEFT JOIN product p ON p.id = oi.product_id
          WHERE oi.order_id = ANY($1::bigint[])
          ORDER BY oi.order_id DESC, oi.id ASC`,
        [orderIds]
      )
    : { rows: [] };
  const reservations = orderIds.length
    ? await pool.query(
        `SELECT id,
                order_id,
                product_id,
                variant_id,
                (
                  SELECT stock_quantity
                    FROM product_variant pv
                   WHERE pv.id = inventory_reservation.variant_id
                   LIMIT 1
                ) AS variant_stock_quantity,
                quantity,
                status,
                expires_at,
                released_at,
                consumed_at,
                created_at
           FROM inventory_reservation
          WHERE order_id = ANY($1::bigint[])
          ORDER BY order_id DESC, id ASC`,
        [orderIds]
      )
    : { rows: [] };

  console.log(
    JSON.stringify(
      {
        merchantId,
        merchants: merchants.rows,
        orders: orders.rows,
        assignments: assignments.rows,
        activeDeliveryDrivers: drivers.rows,
        pendingNoDriver: pendingNoDriver.rows,
        history: history.rows,
        items: items.rows,
        reservations: reservations.rows,
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
