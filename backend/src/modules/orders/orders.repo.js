import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

const FIXED_SERVICE_FEE = 500;
const FIXED_DELIVERY_FEE = 1000;

function statusText(status) {
  switch (status) {
    case "pending":
      return "قيد الانتظار";
    case "preparing":
      return "قيد التحضير";
    case "ready_for_delivery":
      return "جاهز للتوصيل";
    case "on_the_way":
      return "في الطريق";
    case "delivered":
      return "تم التسليم";
    case "cancelled":
      return "تم الإلغاء";
    default:
      return status;
  }
}

const orderSelect = `
  SELECT
    o.*,
    m.name AS merchant_name,
    m.type AS merchant_type,
    m.owner_user_id AS owner_user_id,
    c.image_url AS customer_image_url,
    d.id AS delivery_id,
    d.full_name AS delivery_full_name,
    d.phone AS delivery_phone
  FROM customer_order o
  JOIN merchant m ON m.id = o.merchant_id
  LEFT JOIN app_user c ON c.id = o.customer_user_id
  LEFT JOIN app_user d ON d.id = o.delivery_user_id
`;

function periodStartExpression(period) {
  switch (period) {
    case "day":
      return "DATE_TRUNC('day', NOW())";
    case "month":
      return "DATE_TRUNC('month', NOW())";
    case "year":
      return "DATE_TRUNC('year', NOW())";
    default:
      return null;
  }
}

async function attachItems(orderRows) {
  if (!orderRows.length) return [];

  const ids = orderRows.map((o) => o.id);
  const itemsResult = await q(
    `SELECT id, order_id, product_id, product_name, unit_price, quantity, line_total
     FROM order_item
     WHERE order_id = ANY($1::bigint[])
     ORDER BY id ASC`,
    [ids]
  );

  const map = new Map();
  for (const item of itemsResult.rows) {
    const key = String(item.order_id);
    const list = map.get(key) || [];
    list.push(item);
    map.set(key, list);
  }

  return orderRows.map((row) => ({
    ...row,
    items: map.get(String(row.id)) || [],
  }));
}

export async function listDeliveryAgents() {
  const r = await q(
    `SELECT id, full_name, phone
     FROM app_user
     WHERE role='delivery'
     ORDER BY id DESC`
  );
  return r.rows;
}

export async function createOrderWithItems({
  customer,
  deliveryAddress,
  merchantId,
  note,
  imageUrl,
  normalizedItems,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const merchantResult = await client.query(
      `SELECT id, name, is_open, is_disabled, owner_user_id
       FROM merchant
       WHERE id=$1`,
      [merchantId]
    );
    const merchant = merchantResult.rows[0];
    if (!merchant) {
      const err = new Error("MERCHANT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    if (!merchant.is_open) {
      const err = new Error("MERCHANT_CLOSED");
      err.status = 400;
      throw err;
    }
    if (merchant.is_disabled) {
      const err = new Error("MERCHANT_DISABLED");
      err.status = 400;
      throw err;
    }

    const productIds = normalizedItems.map((x) => x.productId);
    const productsResult = await client.query(
      `SELECT id, merchant_id, name, price, discounted_price, free_delivery, is_available
       FROM product
       WHERE id = ANY($1::bigint[])`,
      [productIds]
    );

    const productMap = new Map(productsResult.rows.map((p) => [String(p.id), p]));
    const calculatedItems = [];
    let subtotal = 0;
    let hasFreeDeliveryOffer = false;

    for (const item of normalizedItems) {
      const product = productMap.get(String(item.productId));
      if (!product) {
        const err = new Error("PRODUCT_NOT_FOUND");
        err.status = 404;
        throw err;
      }
      if (String(product.merchant_id) !== String(merchantId)) {
        const err = new Error("PRODUCT_MERCHANT_MISMATCH");
        err.status = 400;
        throw err;
      }
      if (!product.is_available) {
        const err = new Error("PRODUCT_UNAVAILABLE");
        err.status = 400;
        throw err;
      }

      if (product.free_delivery) {
        hasFreeDeliveryOffer = true;
      }

      const unitPrice = Number(product.discounted_price ?? product.price);
      const lineTotal = unitPrice * item.quantity;
      subtotal += lineTotal;

      calculatedItems.push({
        productId: product.id,
        productName: product.name,
        unitPrice,
        quantity: item.quantity,
        lineTotal,
      });
    }

    const serviceFee = subtotal > 0 ? FIXED_SERVICE_FEE : 0;
    const deliveryFee = hasFreeDeliveryOffer ? 0 : FIXED_DELIVERY_FEE;
    const totalAmount = subtotal + serviceFee + deliveryFee;

    const city = deliveryAddress?.city?.trim() || "مدينة بسماية";
    const block = deliveryAddress?.block?.trim() || customer.block;
    const buildingNumber =
      deliveryAddress?.building_number?.trim() ||
      customer.building_number;
    const apartment =
      deliveryAddress?.apartment?.trim() ||
      customer.apartment;

    const orderResult = await client.query(
      `INSERT INTO customer_order
        (
          merchant_id,
          customer_user_id,
          status,
          customer_full_name,
          customer_phone,
          customer_city,
          customer_block,
          customer_building_number,
          customer_apartment,
          note,
          image_url,
          subtotal,
          delivery_fee,
          total_amount
        )
       VALUES ($1,$2,'pending',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       RETURNING *`,
      [
        merchantId,
        customer.id,
        customer.full_name,
        customer.phone,
        city,
        block,
        buildingNumber,
        apartment,
        note || null,
        imageUrl || null,
        subtotal,
        deliveryFee,
        totalAmount,
      ]
    );
    const order = orderResult.rows[0];

    for (const item of calculatedItems) {
      await client.query(
        `INSERT INTO order_item
          (order_id, product_id, product_name, unit_price, quantity, line_total)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [
          order.id,
          item.productId,
          item.productName,
          item.unitPrice,
          item.quantity,
          item.lineTotal,
        ]
      );
    }

    await client.query("COMMIT");

    const hydratedResult = await q(
      `${orderSelect}
       WHERE o.id=$1`,
      [order.id]
    );

    const [hydrated] = await attachItems(hydratedResult.rows);

    await createManyNotifications([
      {
        userId: customer.id,
        type: "order_created",
        title: "تم إنشاء الطلب",
        body: `تم إنشاء طلبك لدى ${merchant.name} بنجاح`,
        orderId: order.id,
        merchantId: merchant.id,
        payload: {
          orderId: order.id,
          status: order.status,
        },
      },
      merchant.owner_user_id
        ? {
            userId: merchant.owner_user_id,
            type: "owner_new_order",
            title: "طلب جديد",
            body: `طلب جديد رقم #${order.id} لدى ${merchant.name}`,
            orderId: order.id,
            merchantId: merchant.id,
            payload: {
              orderId: order.id,
              status: order.status,
            },
          }
        : null,
    ].filter(Boolean));

    return hydrated;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function listCustomerOrders(customerUserId) {
  const r = await q(
    `${orderSelect}
     WHERE o.customer_user_id=$1
     ORDER BY o.id DESC`,
    [customerUserId]
  );
  return attachItems(r.rows);
}

export async function findCustomerOrder(customerUserId, orderId) {
  const r = await q(
    `${orderSelect}
     WHERE o.customer_user_id=$1
       AND o.id=$2`,
    [customerUserId, orderId]
  );
  const rows = await attachItems(r.rows);
  return rows[0] || null;
}

export async function confirmOrderDelivered(customerUserId, orderId) {
  const r = await q(
    `UPDATE customer_order
     SET customer_confirmed_at = COALESCE(customer_confirmed_at, NOW())
     WHERE id=$1
       AND customer_user_id=$2
       AND status='delivered'
     RETURNING
       id,
       merchant_id,
       delivery_user_id,
       (SELECT owner_user_id FROM merchant WHERE id = customer_order.merchant_id) AS owner_user_id`,
    [orderId, customerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.delivery_user_id
        ? {
            userId: row.delivery_user_id,
            type: "delivery_customer_confirmed",
            title: "تأكيد استلام",
            body: `الزبون أكد استلام الطلب #${row.id}`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
            },
          }
        : null,
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_customer_confirmed",
            title: "تم تأكيد الاستلام",
            body: `الزبون أكد استلام الطلب #${row.id}`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function rateDelivery(customerUserId, orderId, rating, review) {
  const r = await q(
    `UPDATE customer_order
     SET delivery_rating=$1,
         delivery_review=$2,
         rated_at=NOW()
     WHERE id=$3
       AND customer_user_id=$4
       AND status='delivered'
       AND delivery_user_id IS NOT NULL
     RETURNING
       id,
       merchant_id,
       delivery_user_id,
       (SELECT owner_user_id FROM merchant WHERE id = customer_order.merchant_id) AS owner_user_id`,
    [rating, review || null, orderId, customerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.delivery_user_id
        ? {
            userId: row.delivery_user_id,
            type: "delivery_rated",
            title: "تقييم جديد",
            body: `تم تقييمك على الطلب #${row.id} بـ ${rating}/5`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              rating,
            },
          }
        : null,
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_delivery_rated",
            title: "تقييم توصيل",
            body: `تم تقييم الدلفري في الطلب #${row.id} بـ ${rating}/5`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              rating,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function rateMerchant(customerUserId, orderId, rating, review) {
  const r = await q(
    `UPDATE customer_order
     SET merchant_rating=$1,
         merchant_review=$2,
         merchant_rated_at=NOW()
     WHERE id=$3
       AND customer_user_id=$4
       AND status='delivered'
     RETURNING
       id,
       merchant_id,
       (SELECT owner_user_id FROM merchant WHERE id = customer_order.merchant_id) AS owner_user_id`,
    [rating, review || null, orderId, customerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_merchant_rated",
            title: "تقييم متجر جديد",
            body: `تم تقييم المتجر في الطلب #${row.id} بـ ${rating}/5`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              rating,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function listOwnerCurrentOrders(ownerUserId) {
  const r = await q(
    `${orderSelect}
     JOIN merchant mo ON mo.id = o.merchant_id
     WHERE mo.owner_user_id=$1
       AND o.status IN ('pending','preparing','ready_for_delivery','on_the_way')
     ORDER BY o.id DESC`,
    [ownerUserId]
  );
  return attachItems(r.rows);
}

export async function listOwnerOrderHistory(ownerUserId, archiveDate) {
  const params = [ownerUserId];
  let dateSql = "";
  if (archiveDate) {
    params.push(archiveDate);
    dateSql = "AND DATE(o.delivered_at) = $2";
  }

  const r = await q(
    `${orderSelect}
     JOIN merchant mo ON mo.id = o.merchant_id
     WHERE mo.owner_user_id=$1
       AND o.archived_by_delivery = TRUE
       ${dateSql}
     ORDER BY o.id DESC`,
    params
  );
  return attachItems(r.rows);
}

export async function listAdminOrdersForReport(period) {
  const since = periodStartExpression(period);
  if (!since) {
    const err = new Error("INVALID_PERIOD");
    err.status = 400;
    throw err;
  }

  const r = await q(
    `${orderSelect}
     WHERE o.created_at >= ${since}
     ORDER BY o.created_at DESC`,
    []
  );
  return attachItems(r.rows);
}

export async function listOwnerOrdersForReport(ownerUserId, period) {
  const since = periodStartExpression(period);
  if (!since) {
    const err = new Error("INVALID_PERIOD");
    err.status = 400;
    throw err;
  }

  const r = await q(
    `${orderSelect}
     WHERE m.owner_user_id = $1
       AND o.created_at >= ${since}
     ORDER BY o.created_at DESC`,
    [ownerUserId]
  );
  return attachItems(r.rows);
}

async function pickLeastLoadedDeliveryAgent(client) {
  const r = await client.query(
    `SELECT
       u.id,
       COUNT(o.id)::int AS active_orders
     FROM app_user u
     LEFT JOIN customer_order o
       ON o.delivery_user_id = u.id
      AND o.status IN ('pending','preparing','ready_for_delivery','on_the_way')
     WHERE u.role = 'delivery'
     GROUP BY u.id
     ORDER BY active_orders ASC, u.id ASC
     LIMIT 1`
  );

  return r.rows[0] ? Number(r.rows[0].id) : null;
}

export async function updateOwnerOrderStatus(
  ownerUserId,
  orderId,
  status,
  estimatedPrepMinutes,
  estimatedDeliveryMinutes
) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const updateResult = await client.query(
      `UPDATE customer_order o
       SET status=$1::order_status,
           estimated_prep_minutes=COALESCE($2::int, o.estimated_prep_minutes),
           estimated_delivery_minutes=COALESCE($3::int, o.estimated_delivery_minutes),
           approved_at = CASE
             WHEN $1::order_status <> 'pending'::order_status
              AND o.approved_at IS NULL
             THEN NOW()
             ELSE o.approved_at
           END,
           preparing_started_at = CASE
             WHEN $1::order_status='preparing'::order_status
             THEN COALESCE(o.preparing_started_at, NOW())
             ELSE o.preparing_started_at
           END,
           prepared_at = CASE
             WHEN $1::order_status='ready_for_delivery'::order_status
             THEN COALESCE(o.prepared_at, NOW())
             ELSE o.prepared_at
           END
       FROM merchant m
       WHERE o.id=$4
         AND o.merchant_id=m.id
         AND m.owner_user_id=$5
       RETURNING
         o.id,
         o.merchant_id,
         o.status,
         o.customer_user_id,
         o.delivery_user_id,
         m.owner_user_id,
         m.name AS merchant_name`,
      [status, estimatedPrepMinutes, estimatedDeliveryMinutes, orderId, ownerUserId]
    );

    const row = updateResult.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return false;
    }

    let deliveryUserId = row.delivery_user_id ? Number(row.delivery_user_id) : null;

    if (status === "ready_for_delivery" && !deliveryUserId) {
      const pickedDeliveryUserId = await pickLeastLoadedDeliveryAgent(client);
      if (pickedDeliveryUserId) {
        const assignResult = await client.query(
          `UPDATE customer_order
           SET delivery_user_id = $2
           WHERE id = $1
             AND delivery_user_id IS NULL
           RETURNING delivery_user_id`,
          [row.id, pickedDeliveryUserId]
        );

        if (assignResult.rows[0]?.delivery_user_id) {
          deliveryUserId = Number(assignResult.rows[0].delivery_user_id);
        }
      }
    }

    await client.query("COMMIT");

    await createManyNotifications(
      [
        {
          userId: row.customer_user_id,
          type: "customer_order_status",
          title: "تحديث حالة الطلب",
          body: `حالة الطلب #${row.id}: ${statusText(status)}`,
          orderId: row.id,
          merchantId: row.merchant_id,
          payload: {
            orderId: row.id,
            status,
          },
        },
        status === "cancelled" && deliveryUserId
          ? {
              userId: deliveryUserId,
              type: "delivery_order_cancelled",
              title: "تم إلغاء طلب",
              body: `تم إلغاء الطلب #${row.id}`,
              orderId: row.id,
              merchantId: row.merchant_id,
              payload: {
                orderId: row.id,
                status,
              },
            }
          : null,
        status === "ready_for_delivery" && deliveryUserId
          ? {
              userId: deliveryUserId,
              type: "delivery_order_ready",
              title: "طلب جاهز للتوصيل",
              body: `الطلب #${row.id} من ${row.merchant_name} جاهز للتوصيل`,
              orderId: row.id,
              merchantId: row.merchant_id,
              payload: {
                orderId: row.id,
                status,
              },
            }
          : null,
      ].filter(Boolean)
    );

    return true;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function assignDeliveryToOwnerOrder(ownerUserId, orderId, deliveryUserId) {
  const deliveryCheck = await q(
    `SELECT id
     FROM app_user
     WHERE id=$1 AND role='delivery'`,
    [deliveryUserId]
  );
  if (!deliveryCheck.rows[0]) {
    const err = new Error("DELIVERY_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const r = await q(
    `UPDATE customer_order o
     SET delivery_user_id=$1
     FROM merchant m
     WHERE o.id=$2
       AND o.merchant_id=m.id
       AND m.owner_user_id=$3
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.name AS merchant_name`,
    [deliveryUserId, orderId, ownerUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications([
    {
      userId: Number(deliveryUserId),
      type: "delivery_assigned_by_owner",
      title: "إسناد طلب جديد",
      body: `تم إسناد الطلب #${row.id} من ${row.merchant_name} إليك`,
      orderId: row.id,
      merchantId: row.merchant_id,
      payload: {
        orderId: row.id,
        assignedBy: "owner",
      },
    },
    {
      userId: row.customer_user_id,
      type: "customer_delivery_assigned",
      title: "تم تعيين الدلفري",
      body: `تم تعيين دلفري على طلبك #${row.id}`,
      orderId: row.id,
      merchantId: row.merchant_id,
      payload: {
        orderId: row.id,
      },
    },
  ]);

  return true;
}

export async function listDeliveryCurrentOrders(deliveryUserId) {
  const r = await q(
    `${orderSelect}
     WHERE (o.delivery_user_id=$1 AND o.status IN ('pending','preparing','ready_for_delivery','on_the_way'))
        OR (o.delivery_user_id IS NULL AND o.status='ready_for_delivery')
     ORDER BY o.id DESC`,
    [deliveryUserId]
  );
  return attachItems(r.rows);
}

export async function listDeliveryHistory(deliveryUserId, archiveDate) {
  const params = [deliveryUserId];
  let dateSql = "";
  if (archiveDate) {
    params.push(archiveDate);
    dateSql = "AND DATE(o.delivered_at) = $2";
  }

  const r = await q(
    `${orderSelect}
     WHERE o.delivery_user_id=$1
       AND o.archived_by_delivery = TRUE
       ${dateSql}
     ORDER BY o.id DESC`,
    params
  );
  return attachItems(r.rows);
}

export async function claimDeliveryOrder(deliveryUserId, orderId) {
  const r = await q(
    `UPDATE customer_order o
     SET delivery_user_id=$1
     FROM merchant m
     WHERE o.id=$2
       AND o.status='ready_for_delivery'
       AND o.delivery_user_id IS NULL
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id,
       m.name AS merchant_name`,
    [deliveryUserId, orderId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_delivery_claimed",
            title: "تم استلام الطلب من الدلفري",
            body: `الدلفري استلم الطلب #${row.id} من ${row.merchant_name}`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
            },
          }
        : null,
      {
        userId: row.customer_user_id,
        type: "customer_delivery_claimed",
        title: "الدلفري استلم الطلب",
        body: `تم استلام طلبك #${row.id} من قبل الدلفري`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
        },
      },
    ].filter(Boolean)
  );

  return true;
}

export async function markOrderOnTheWay(deliveryUserId, orderId, estimatedDeliveryMinutes) {
  const r = await q(
    `UPDATE customer_order o
     SET status='on_the_way',
         picked_up_at=COALESCE(picked_up_at, NOW()),
         estimated_delivery_minutes=COALESCE($1, o.estimated_delivery_minutes)
     FROM merchant m
     WHERE o.id=$2
       AND o.delivery_user_id=$3
       AND o.status IN ('ready_for_delivery', 'on_the_way')
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id`,
    [estimatedDeliveryMinutes, orderId, deliveryUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      {
        userId: row.customer_user_id,
        type: "customer_order_on_the_way",
        title: "الطلب في الطريق",
        body: `الطلب #${row.id} أصبح في الطريق إليك`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
          status: "on_the_way",
          etaMinMinutes: 7,
          etaMaxMinutes: 10,
        },
      },
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_order_on_the_way",
            title: "تم استلام الطلب للتوصيل",
            body: `الطلب #${row.id} خرج للتوصيل`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              status: "on_the_way",
              etaMinMinutes: 7,
              etaMaxMinutes: 10,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function markOrderDelivered(deliveryUserId, orderId) {
  const r = await q(
    `UPDATE customer_order o
     SET status='delivered',
         delivered_at=COALESCE(delivered_at, NOW())
     FROM merchant m
     WHERE o.id=$1
       AND o.delivery_user_id=$2
       AND o.status IN ('on_the_way','ready_for_delivery')
       AND o.merchant_id = m.id
     RETURNING
       o.id,
       o.customer_user_id,
       o.merchant_id,
       m.owner_user_id`,
    [orderId, deliveryUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      {
        userId: row.customer_user_id,
        type: "customer_order_delivered",
        title: "تم توصيل الطلب",
        body: `تم توصيل الطلب #${row.id}، يرجى تأكيد الاستلام`,
        orderId: row.id,
        merchantId: row.merchant_id,
        payload: {
          orderId: row.id,
          status: "delivered",
        },
      },
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_order_delivered",
            title: "تم توصيل طلب",
            body: `تم توصيل الطلب #${row.id} بنجاح`,
            orderId: row.id,
            merchantId: row.merchant_id,
            payload: {
              orderId: row.id,
              status: "delivered",
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function endDeliveryDay(deliveryUserId, archiveDate) {
  const date = archiveDate || new Date().toISOString().slice(0, 10);

  const deliveredRows = await q(
    `UPDATE customer_order
     SET archived_by_delivery=TRUE,
         archived_by_delivery_at=NOW()
     WHERE delivery_user_id=$1
       AND status='delivered'
       AND archived_by_delivery=FALSE
       AND DATE(delivered_at)=$2
     RETURNING total_amount`,
    [deliveryUserId, date]
  );

  const ordersCount = deliveredRows.rows.length;
  const totalAmount = deliveredRows.rows.reduce(
    (sum, row) => sum + Number(row.total_amount || 0),
    0
  );

  await q(
    `INSERT INTO delivery_day_archive
      (delivery_user_id, archive_date, orders_count, total_amount)
     VALUES ($1,$2,$3,$4)
     ON CONFLICT (delivery_user_id, archive_date)
     DO UPDATE
     SET orders_count = delivery_day_archive.orders_count + EXCLUDED.orders_count,
         total_amount = delivery_day_archive.total_amount + EXCLUDED.total_amount`,
    [deliveryUserId, date, ordersCount, totalAmount]
  );

  return { archiveDate: date, ordersCount, totalAmount };
}

export async function listFavoriteProductIds(customerUserId) {
  const r = await q(
    `SELECT product_id
     FROM customer_favorite_product
     WHERE customer_user_id = $1`,
    [Number(customerUserId)]
  );

  return r.rows.map((row) => Number(row.product_id));
}

export async function listFavoriteProducts(customerUserId, merchantId) {
  const params = [Number(customerUserId)];
  let merchantWhere = "";

  if (merchantId) {
    params.push(Number(merchantId));
    merchantWhere = "AND p.merchant_id = $2";
  }

  const r = await q(
    `SELECT
       p.*,
       m.name AS merchant_name,
       m.id AS merchant_id
     FROM customer_favorite_product f
     JOIN product p ON p.id = f.product_id
     JOIN merchant m ON m.id = p.merchant_id
     WHERE f.customer_user_id = $1
       AND p.is_available = TRUE
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
       ${merchantWhere}
     ORDER BY f.created_at DESC`,
    params
  );

  return r.rows;
}

export async function addFavoriteProduct(customerUserId, productId) {
  const insertResult = await q(
    `INSERT INTO customer_favorite_product (customer_user_id, product_id)
     SELECT $1, p.id
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE p.id = $2
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
     ON CONFLICT (customer_user_id, product_id) DO NOTHING
     RETURNING product_id`,
    [Number(customerUserId), Number(productId)]
  );

  if (insertResult.rows[0]) return true;

  const existsResult = await q(
    `SELECT id
     FROM product
     WHERE id = $1`,
    [Number(productId)]
  );

  if (!existsResult.rows[0]) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return true;
}

export async function removeFavoriteProduct(customerUserId, productId) {
  await q(
    `DELETE FROM customer_favorite_product
     WHERE customer_user_id = $1
       AND product_id = $2`,
    [Number(customerUserId), Number(productId)]
  );
}

export async function getOrderForReorder(customerUserId, orderId) {
  const orderResult = await q(
    `SELECT
       id,
       merchant_id,
       note,
       customer_city,
       customer_block,
       customer_building_number,
       customer_apartment
     FROM customer_order
     WHERE id = $1
       AND customer_user_id = $2
       AND status <> 'cancelled'`,
    [Number(orderId), Number(customerUserId)]
  );

  const order = orderResult.rows[0];
  if (!order) return null;

  const itemsResult = await q(
    `SELECT
       product_id,
       SUM(quantity)::int AS quantity
     FROM order_item
     WHERE order_id = $1
       AND product_id IS NOT NULL
     GROUP BY product_id`,
    [Number(order.id)]
  );

  return {
    orderId: Number(order.id),
    merchantId: Number(order.merchant_id),
    note: order.note || null,
    customerCity: order.customer_city || "مدينة بسماية",
    customerBlock: order.customer_block,
    customerBuildingNumber: order.customer_building_number,
    customerApartment: order.customer_apartment,
    items: itemsResult.rows.map((row) => ({
      productId: Number(row.product_id),
      quantity: Number(row.quantity),
    })),
  };
}
