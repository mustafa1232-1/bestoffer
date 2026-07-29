import { q } from "../../config/db.js";

export const CANCELLED_ORDER_STATUSES = new Set([
  "cancelled",
  "cancelled_by_customer",
  "cancelled_by_store",
  "cancelled_by_admin",
]);

export function isCancelledOrderStatus(status) {
  return CANCELLED_ORDER_STATUSES.has(
    String(status || "").trim().toLowerCase()
  );
}

function normalizeVoidReason(reason, fallback = "order_cancelled") {
  const text = String(reason || "").trim();
  if (!text) return fallback;
  return text.slice(0, 160);
}

async function recalculateCouponUsesCountTx(client, couponId) {
  await client.query(
    `UPDATE coupon c
     SET uses_count = COALESCE((
       SELECT COUNT(*)
       FROM coupon_redemption cr
       WHERE cr.coupon_id = c.id
         AND COALESCE(cr.is_void, FALSE) = FALSE
     ), 0)
     WHERE c.id = $1`,
    [Number(couponId)]
  );
}

function normalizeOrderRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    customerUserId:
      row.customer_user_id == null ? null : Number(row.customer_user_id),
    couponId: row.coupon_id == null ? null : Number(row.coupon_id),
    couponCode: row.coupon_code || null,
    couponDiscountTotal: Number(row.coupon_discount_total || 0),
    status: String(row.status || ""),
  };
}

export async function getOrderIncentiveSnapshotTx(client, orderId) {
  const result = await client.query(
    `SELECT
       id,
       customer_user_id,
       coupon_id,
       coupon_code,
       coupon_discount_total,
       status
     FROM customer_order
     WHERE id = $1
     LIMIT 1`,
    [Number(orderId)]
  );
  return normalizeOrderRow(result.rows[0] || null);
}

export async function consumeCouponRedemptionByOrderTx(
  client,
  { couponId, customerId, orderId, discountAmount }
) {
  const normalizedCouponId = Number(couponId || 0);
  const normalizedCustomerId = Number(customerId || 0);
  const normalizedOrderId = Number(orderId || 0);
  const normalizedDiscountAmount = Number(discountAmount || 0);

  if (
    !Number.isInteger(normalizedCouponId) ||
    normalizedCouponId <= 0 ||
    !Number.isInteger(normalizedCustomerId) ||
    normalizedCustomerId <= 0 ||
    !Number.isInteger(normalizedOrderId) ||
    normalizedOrderId <= 0 ||
    normalizedDiscountAmount < 0
  ) {
    // A zero discount is valid — attribution-only (referral) coupons record the
    // redemption with discount_amount = 0.
    return { changed: false, couponId: normalizedCouponId || null };
  }

  const existing = await client.query(
    `SELECT id, is_void
     FROM coupon_redemption
     WHERE coupon_id = $1
       AND order_id = $2
     LIMIT 1
     FOR UPDATE`,
    [normalizedCouponId, normalizedOrderId]
  );

  let changed = false;
  if (existing.rows[0]) {
    if (existing.rows[0].is_void === true) {
      try {
        await client.query(
          `UPDATE coupon_redemption
           SET customer_id = $2,
               discount_amount = $3,
               is_void = FALSE,
               voided_at = NULL,
               void_reason = NULL,
               redeemed_at = COALESCE(redeemed_at, NOW())
           WHERE id = $1`,
          [
            Number(existing.rows[0].id),
            normalizedCustomerId,
            normalizedDiscountAmount,
          ]
        );
      } catch (error) {
        if (String(error?.code || "") === "23505") {
          const conflict = new Error("COUPON_REDEMPTION_ACTIVE_CONFLICT");
          conflict.status = 409;
          throw conflict;
        }
        throw error;
      }
      changed = true;
    }
  } else {
    try {
      await client.query(
        `INSERT INTO coupon_redemption
          (
            coupon_id,
            customer_id,
            order_id,
            discount_amount,
            is_void
          )
         VALUES ($1, $2, $3, $4, FALSE)`,
        [
          normalizedCouponId,
          normalizedCustomerId,
          normalizedOrderId,
          normalizedDiscountAmount,
        ]
      );
    } catch (error) {
      if (String(error?.code || "") === "23505") {
        const conflict = new Error("COUPON_ALREADY_REDEEMED");
        conflict.status = 409;
        throw conflict;
      }
      throw error;
    }
    changed = true;
  }

  if (changed) {
    await recalculateCouponUsesCountTx(client, normalizedCouponId);
  }

  return { changed, couponId: normalizedCouponId };
}

export async function syncCouponRedemptionForOrderStatusTx(
  client,
  { orderId, nextStatus, reason = null }
) {
  const order = await getOrderIncentiveSnapshotTx(client, orderId);
  // A coupon may be attribution-only (zero discount) — still manage its
  // redemption through the order lifecycle. Only skip when there is no coupon.
  if (
    !order ||
    order.couponId == null ||
    order.customerUserId == null
  ) {
    return { changed: false, couponId: order?.couponId || null };
  }

  const shouldVoid = isCancelledOrderStatus(nextStatus);
  const result = await client.query(
    `SELECT id, is_void
     FROM coupon_redemption
     WHERE coupon_id = $1
       AND order_id = $2
     LIMIT 1
     FOR UPDATE`,
    [Number(order.couponId), Number(order.id)]
  );

  const row = result.rows[0] || null;
  let changed = false;

  if (shouldVoid) {
    if (row && row.is_void !== true) {
      await client.query(
        `UPDATE coupon_redemption
         SET is_void = TRUE,
             voided_at = NOW(),
             void_reason = COALESCE($2, void_reason)
         WHERE id = $1`,
        [Number(row.id), normalizeVoidReason(reason, "order_cancelled")]
      );
      changed = true;
    }
  } else if (row) {
    if (row.is_void === true) {
      try {
        await client.query(
          `UPDATE coupon_redemption
           SET is_void = FALSE,
               voided_at = NULL,
               void_reason = NULL
           WHERE id = $1`,
          [Number(row.id)]
        );
      } catch (error) {
        if (String(error?.code || "") === "23505") {
          const conflict = new Error("COUPON_REDEMPTION_ACTIVE_CONFLICT");
          conflict.status = 409;
          throw conflict;
        }
        throw error;
      }
      changed = true;
    }
  } else {
    const consumed = await consumeCouponRedemptionByOrderTx(client, {
      couponId: order.couponId,
      customerId: order.customerUserId,
      orderId: order.id,
      discountAmount: order.couponDiscountTotal,
    });
    return consumed;
  }

  if (changed) {
    await recalculateCouponUsesCountTx(client, Number(order.couponId));
  }

  return { changed, couponId: Number(order.couponId) };
}

export async function syncOfferUsageForOrderStatusTx(
  client,
  { orderId, nextStatus, reason = null }
) {
  const shouldVoid = isCancelledOrderStatus(nextStatus);
  const existing = await client.query(
    `SELECT id, is_void
     FROM merchant_offer_usage
     WHERE order_id = $1
     FOR UPDATE`,
    [Number(orderId)]
  );

  const ids = existing.rows
    .filter((row) => (shouldVoid ? row.is_void !== true : row.is_void === true))
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);

  if (ids.length === 0) {
    return { changed: false, count: 0 };
  }

  if (shouldVoid) {
    await client.query(
      `UPDATE merchant_offer_usage
       SET is_void = TRUE,
           voided_at = COALESCE(voided_at, NOW()),
           void_reason = COALESCE($2, void_reason)
       WHERE id = ANY($1::bigint[])`,
      [ids, normalizeVoidReason(reason, "order_cancelled")]
    );
  } else {
    await client.query(
      `UPDATE merchant_offer_usage
       SET is_void = FALSE,
           voided_at = NULL,
           void_reason = NULL
       WHERE id = ANY($1::bigint[])`,
      [ids]
    );
  }

  return {
    changed: true,
    count: ids.length,
  };
}

export async function syncOrderIncentiveConsumptionForStatusTx(
  client,
  { orderId, nextStatus, reason = null }
) {
  const [coupon, offers] = await Promise.all([
    syncCouponRedemptionForOrderStatusTx(client, {
      orderId,
      nextStatus,
      reason,
    }),
    syncOfferUsageForOrderStatusTx(client, {
      orderId,
      nextStatus,
      reason,
    }),
  ]);

  return {
    coupon,
    offers,
  };
}

export async function rebuildCouponUsesCounts() {
  await q(
    `UPDATE coupon c
     SET uses_count = COALESCE(src.active_count, 0)
     FROM (
       SELECT coupon_id, COUNT(*)::int AS active_count
       FROM coupon_redemption
       WHERE COALESCE(is_void, FALSE) = FALSE
       GROUP BY coupon_id
     ) src
     WHERE c.id = src.coupon_id`
  );
  await q(
    `UPDATE coupon c
     SET uses_count = 0
     WHERE NOT EXISTS (
       SELECT 1
       FROM coupon_redemption cr
       WHERE cr.coupon_id = c.id
         AND COALESCE(cr.is_void, FALSE) = FALSE
     )`
  );
}
