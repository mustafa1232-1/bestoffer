import { q } from "../../config/db.js";

/**
 * The coupon `scope_kind` column is NOT NULL with a column default of
 * 'merchant'. It MUST be derived explicitly on insert (never left to the
 * default) so global coupons don't silently become unmatchable 'merchant'
 * coupons with a NULL merchant_id. Validation matches on this value.
 */
export function resolveCouponScopeKind({ merchantId, companyId } = {}) {
  if (companyId) return "company";
  if (merchantId) return "merchant";
  return "global";
}

/**
 * Look up a coupon by its code and validate it's usable:
 * - active, within valid dates, not exceeded max_uses
 * - optionally scoped to a merchant
 * - customer hasn't already used it
 * Returns the coupon row or null.
 */
export async function findValidCoupon(code, { customerId, merchantId, orderTotal }) {
  const r = await q(
    `SELECT c.*
     FROM coupon c
     LEFT JOIN merchant target_merchant ON target_merchant.id = $2
     WHERE UPPER(c.code) = UPPER($1)
       AND c.is_active = TRUE
       AND (c.valid_from  IS NULL OR c.valid_from  <= NOW())
       AND (c.valid_until IS NULL OR c.valid_until >= NOW())
       AND (c.max_uses    IS NULL OR c.uses_count < c.max_uses)
       AND (
         (c.scope_kind = 'global' AND c.merchant_id IS NULL AND c.company_id IS NULL)
         OR (c.scope_kind = 'merchant' AND c.merchant_id = $2)
         OR (
           c.scope_kind = 'company'
           AND target_merchant.company_id IS NOT NULL
           AND c.company_id = target_merchant.company_id
           AND (
             c.company_applies_to_all_branches = TRUE
             OR EXISTS (
               SELECT 1
               FROM company_coupon_target cct
               WHERE cct.coupon_id = c.id
                 AND cct.merchant_id = $2
             )
           )
         )
       )
       AND (c.min_order_total = 0  OR $3 >= c.min_order_total)
       AND NOT EXISTS (
         SELECT 1 FROM coupon_redemption cr
         WHERE cr.coupon_id = c.id
           AND cr.customer_id = $4
           AND COALESCE(cr.is_void, FALSE) = FALSE
       )
     LIMIT 1`,
    [code, merchantId || null, Number(orderTotal || 0), customerId]
  );
  return r.rows[0] || null;
}

/**
 * Calculate the discount amount for a coupon against an order total.
 */
export function calcDiscount(coupon, orderTotal) {
  const total = Number(orderTotal);
  if (coupon.discount_type === "percent") {
    return Math.round((total * Number(coupon.discount_value)) / 100);
  }
  return Math.min(Number(coupon.discount_value), total);
}

/**
 * Record that a customer used a coupon on an order.
 */
export async function redeemCoupon(couponId, customerId, orderId, discountAmount) {
  await q(
    `INSERT INTO coupon_redemption
      (
        coupon_id,
        customer_id,
        order_id,
        discount_amount,
        is_void
      )
     VALUES ($1, $2, $3, $4, FALSE)`,
    [couponId, customerId, orderId || null, discountAmount]
  );
  await q(
    `UPDATE coupon
     SET uses_count = COALESCE((
       SELECT COUNT(*)
       FROM coupon_redemption cr
       WHERE cr.coupon_id = coupon.id
         AND COALESCE(cr.is_void, FALSE) = FALSE
     ), 0)
     WHERE id = $1`,
    [couponId]
  );
}

/**
 * Customer feed: active shopping coupons that can still be used by this customer.
 * Includes scope metadata and a compact list of target merchants (when scoped).
 */
export async function listCustomerCoupons({
  customerId,
  merchantId = null,
  limit = 80,
} = {}) {
  const safeCustomerId = Number(customerId);
  const safeMerchantId = merchantId == null ? null : Number(merchantId);
  const safeLimit = Math.max(1, Math.min(120, Number(limit) || 80));

  const r = await q(
    `SELECT
       c.id,
       c.code,
       c.description,
       c.discount_type,
       c.discount_value,
       c.min_order_total,
       c.max_uses,
       c.uses_count,
       c.valid_from,
       c.valid_until,
       c.is_active,
       c.scope_kind,
       c.merchant_id,
       c.company_id,
       c.company_applies_to_all_branches,
       c.created_at,
       m.name AS merchant_name,
       comp.name AS company_name,
       CASE
         WHEN c.max_uses IS NULL OR c.max_uses <= 0 THEN NULL
         ELSE GREATEST(0, c.max_uses - c.uses_count)
       END::INT AS remaining_uses_total,
       COALESCE(targets.target_merchants, '[]'::jsonb) AS target_merchants
     FROM coupon c
     LEFT JOIN merchant m ON m.id = c.merchant_id
     LEFT JOIN company comp ON comp.id = c.company_id
     LEFT JOIN LATERAL (
       SELECT COALESCE(
         jsonb_agg(
           jsonb_build_object(
             'id', target.id,
             'name', target.name,
             'type', target.type::text
           )
           ORDER BY target.name ASC
         ),
         '[]'::jsonb
       ) AS target_merchants
       FROM (
         SELECT DISTINCT m_target.id, m_target.name, m_target.type
         FROM merchant m_target
         WHERE (
           (c.scope_kind = 'merchant' AND m_target.id = c.merchant_id)
           OR (
             c.scope_kind = 'company'
             AND c.company_id IS NOT NULL
             AND (
               (c.company_applies_to_all_branches = TRUE AND m_target.company_id = c.company_id)
               OR (
                 c.company_applies_to_all_branches = FALSE
                 AND EXISTS (
                   SELECT 1
                   FROM company_coupon_target cct_target
                   WHERE cct_target.coupon_id = c.id
                     AND cct_target.merchant_id = m_target.id
                 )
               )
             )
           )
         )
           AND m_target.is_approved = TRUE
           AND COALESCE(m_target.is_disabled, FALSE) = FALSE
         ORDER BY m_target.name ASC
         LIMIT 40
       ) target
     ) targets ON TRUE
     WHERE c.is_active = TRUE
       AND (c.valid_from IS NULL OR c.valid_from <= NOW())
       AND (c.valid_until IS NULL OR c.valid_until >= NOW())
       AND (c.max_uses IS NULL OR c.uses_count < c.max_uses)
       AND NOT EXISTS (
         SELECT 1
         FROM coupon_redemption cr
         WHERE cr.coupon_id = c.id
           AND cr.customer_id = $1
           AND COALESCE(cr.is_void, FALSE) = FALSE
       )
       AND (
         c.scope_kind = 'global'
         OR (
           c.scope_kind = 'merchant'
           AND m.is_approved = TRUE
           AND COALESCE(m.is_disabled, FALSE) = FALSE
         )
         OR (
           c.scope_kind = 'company'
           AND c.company_id IS NOT NULL
           AND (
             (
               c.company_applies_to_all_branches = TRUE
               AND EXISTS (
                 SELECT 1
                 FROM merchant m_all
                 WHERE m_all.company_id = c.company_id
                   AND m_all.is_approved = TRUE
                   AND COALESCE(m_all.is_disabled, FALSE) = FALSE
               )
             )
             OR (
               c.company_applies_to_all_branches = FALSE
               AND EXISTS (
                 SELECT 1
                 FROM company_coupon_target cct_any
                 JOIN merchant m_any ON m_any.id = cct_any.merchant_id
                 WHERE cct_any.coupon_id = c.id
                   AND m_any.is_approved = TRUE
                   AND COALESCE(m_any.is_disabled, FALSE) = FALSE
               )
             )
           )
         )
       )
       AND (
         $2::bigint IS NULL
         OR c.scope_kind = 'global'
         OR (c.scope_kind = 'merchant' AND c.merchant_id = $2)
         OR (
           c.scope_kind = 'company'
           AND c.company_id IS NOT NULL
           AND (
             (
               c.company_applies_to_all_branches = TRUE
               AND EXISTS (
                 SELECT 1
                 FROM merchant m_scope
                 WHERE m_scope.id = $2
                   AND m_scope.company_id = c.company_id
                   AND m_scope.is_approved = TRUE
                   AND COALESCE(m_scope.is_disabled, FALSE) = FALSE
               )
             )
             OR (
               c.company_applies_to_all_branches = FALSE
               AND EXISTS (
                 SELECT 1
                 FROM company_coupon_target cct_scope
                 JOIN merchant m_scope_target ON m_scope_target.id = cct_scope.merchant_id
                 WHERE cct_scope.coupon_id = c.id
                   AND cct_scope.merchant_id = $2
                   AND m_scope_target.is_approved = TRUE
                   AND COALESCE(m_scope_target.is_disabled, FALSE) = FALSE
               )
             )
           )
         )
       )
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT $3`,
    [safeCustomerId, safeMerchantId, safeLimit]
  );
  return r.rows;
}

// ── Admin CRUD ────────────────────────────────────────────────────────────────

export async function createCoupon({
  code, description, discountType, discountValue, minOrderTotal,
  maxUses, merchantId, validFrom, validUntil, createdBy,
}) {
  // scope_kind MUST be set explicitly (see resolveCouponScopeKind). The column
  // defaults to 'merchant', so omitting it made global coupons (no merchant_id)
  // default to 'merchant' with a NULL merchant_id — which the validation query
  // can never match, making every global coupon report as invalid.
  const resolvedMerchantId = merchantId ? Number(merchantId) : null;
  const scopeKind = resolveCouponScopeKind({ merchantId: resolvedMerchantId });
  const r = await q(
    `INSERT INTO coupon
       (code, description, discount_type, discount_value, min_order_total,
        max_uses, merchant_id, scope_kind, valid_from, valid_until, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING *`,
    [
      code.toUpperCase().trim(), description || null, discountType,
      Number(discountValue), Number(minOrderTotal || 0),
      maxUses ? Number(maxUses) : null,
      resolvedMerchantId,
      scopeKind,
      validFrom || null, validUntil || null, createdBy,
    ]
  );
  return r.rows[0];
}

export async function listCoupons({
  merchantId,
  includeGlobal = true,
  activeOnly = false,
  limit = 50,
  offset = 0,
} = {}) {
  const scope = buildCouponScope({
    alias: "c",
    merchantId,
    includeGlobal,
  });
  const conditions = [...scope.conditions];
  const params = [...scope.params];
  let idx = scope.nextParamIndex;

  if (activeOnly) {
    conditions.push(`c.is_active = TRUE`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
  params.push(limit, offset);

  const r = await q(
    `SELECT
       c.*,
       m.name AS merchant_name,
       COALESCE(metrics.completed_orders_count, 0)::INT AS completed_orders_count,
       COALESCE(metrics.gross_sales_total, 0)::NUMERIC(12,2) AS gross_sales_total,
       COALESCE(metrics.discount_total, 0)::NUMERIC(12,2) AS discount_total,
       COALESCE(metrics.net_sales_total, 0)::NUMERIC(12,2) AS net_sales_total,
       COALESCE(metrics.avg_order_value, 0)::NUMERIC(12,2) AS avg_order_value
     FROM coupon c
     LEFT JOIN merchant m ON m.id = c.merchant_id
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*) FILTER (
           WHERE o.id IS NOT NULL
             AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
         )::INT AS completed_orders_count,
         COALESCE(SUM(
           CASE
             WHEN o.id IS NOT NULL
              AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
             THEN COALESCE(o.subtotal, 0)
                + COALESCE(o.coupon_discount_total, 0)
                + COALESCE(o.service_fee, 0)
                + COALESCE(o.delivery_fee, 0)
             ELSE 0
           END
         ), 0)::NUMERIC(12,2) AS gross_sales_total,
         COALESCE(SUM(
           CASE
             WHEN o.id IS NOT NULL
              AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
             THEN COALESCE(o.coupon_discount_total, cr.discount_amount, 0)
             ELSE 0
           END
         ), 0)::NUMERIC(12,2) AS discount_total,
         COALESCE(SUM(
           CASE
             WHEN o.id IS NOT NULL
              AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
             THEN COALESCE(o.total_amount, 0)
             ELSE 0
           END
         ), 0)::NUMERIC(12,2) AS net_sales_total,
         COALESCE(AVG(
           CASE
             WHEN o.id IS NOT NULL
              AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
             THEN COALESCE(o.total_amount, 0)
             ELSE NULL
           END
         ), 0)::NUMERIC(12,2) AS avg_order_value
       FROM coupon_redemption cr
       LEFT JOIN customer_order o ON o.id = cr.order_id
       WHERE cr.coupon_id = c.id
         AND COALESCE(cr.is_void, FALSE) = FALSE
     ) metrics ON TRUE
     ${where}
     ORDER BY c.created_at DESC
     LIMIT $${idx} OFFSET $${idx + 1}`,
    params
  );
  return r.rows;
}

export async function getCouponStats({
  merchantId,
  includeGlobal = true,
  days = 30,
} = {}) {
  const normalizedDays = Math.max(7, Math.min(365, Number(days) || 30));
  const scopeCoupon = buildCouponScope({
    alias: "c",
    merchantId,
    includeGlobal,
  });
  const scopeRedemption = buildCouponScope({
    alias: "c",
    merchantId,
    includeGlobal,
  });

  const summaryQuery = `
    SELECT
      COUNT(*)::INT AS total_coupons,
      COUNT(*) FILTER (WHERE c.is_active = TRUE)::INT AS active_coupons,
      COUNT(*) FILTER (WHERE c.is_active = FALSE)::INT AS inactive_coupons,
      COUNT(*) FILTER (
        WHERE c.valid_until IS NOT NULL AND c.valid_until < NOW()
      )::INT AS expired_coupons,
      COUNT(*) FILTER (
        WHERE c.valid_from IS NOT NULL AND c.valid_from > NOW()
      )::INT AS scheduled_coupons,
      COALESCE(SUM(c.uses_count), 0)::INT AS total_uses,
      COALESCE(
        SUM(
          CASE
            WHEN c.max_uses IS NOT NULL AND c.max_uses > 0
            THEN LEAST(c.uses_count, c.max_uses)
            ELSE c.uses_count
          END
        ),
        0
      )::INT AS used_slots,
      COALESCE(
        SUM(
          CASE
            WHEN c.max_uses IS NOT NULL AND c.max_uses > 0
            THEN c.max_uses
            ELSE 0
          END
        ),
        0
      )::INT AS bounded_slots,
      COALESCE(SUM(metrics.gross_sales_total), 0)::NUMERIC(12,2) AS gross_sales_total,
      COALESCE(SUM(metrics.discount_total), 0)::NUMERIC(12,2) AS coupon_discount_total,
      COALESCE(SUM(metrics.net_sales_total), 0)::NUMERIC(12,2) AS net_sales_total,
      COALESCE(AVG(NULLIF(metrics.avg_order_value, 0)), 0)::NUMERIC(12,2) AS avg_order_value
    FROM coupon c
    LEFT JOIN LATERAL (
      SELECT
        COALESCE(SUM(
          CASE
            WHEN o.id IS NOT NULL
             AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
            THEN COALESCE(o.subtotal, 0)
               + COALESCE(o.coupon_discount_total, 0)
               + COALESCE(o.service_fee, 0)
               + COALESCE(o.delivery_fee, 0)
            ELSE 0
          END
        ), 0)::NUMERIC(12,2) AS gross_sales_total,
        COALESCE(SUM(
          CASE
            WHEN o.id IS NOT NULL
             AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
            THEN COALESCE(o.coupon_discount_total, cr.discount_amount, 0)
            ELSE 0
          END
        ), 0)::NUMERIC(12,2) AS discount_total,
        COALESCE(SUM(
          CASE
            WHEN o.id IS NOT NULL
             AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
            THEN COALESCE(o.total_amount, 0)
            ELSE 0
          END
        ), 0)::NUMERIC(12,2) AS net_sales_total,
        COALESCE(AVG(
          CASE
            WHEN o.id IS NOT NULL
             AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
            THEN COALESCE(o.total_amount, 0)
            ELSE NULL
          END
        ), 0)::NUMERIC(12,2) AS avg_order_value
      FROM coupon_redemption cr
      LEFT JOIN customer_order o ON o.id = cr.order_id
      WHERE cr.coupon_id = c.id
        AND COALESCE(cr.is_void, FALSE) = FALSE
    ) metrics ON TRUE
    ${
      scopeCoupon.conditions.length
        ? `WHERE ${scopeCoupon.conditions.join(" AND ")}`
        : ""
    }`;
  const summaryResult = await q(summaryQuery, scopeCoupon.params);
  const summary = summaryResult.rows[0] || {};

  const topQuery = `
    SELECT
      c.id,
      c.code,
      c.discount_type,
      c.discount_value,
      c.is_active,
      c.uses_count,
      c.max_uses,
      c.merchant_id,
      m.name AS merchant_name
    FROM coupon c
    LEFT JOIN merchant m ON m.id = c.merchant_id
    ${
      scopeCoupon.conditions.length
        ? `WHERE ${scopeCoupon.conditions.join(" AND ")}`
        : ""
    }
    ORDER BY c.uses_count DESC, c.created_at DESC
    LIMIT 5`;
  const topResult = await q(topQuery, scopeCoupon.params);

  const timelineParams = [
    ...scopeRedemption.params,
    normalizedDays,
  ];
  const timelineDaysParam = timelineParams.length;
  const timelineQuery = `
    SELECT
      DATE_TRUNC('day', cr.redeemed_at)::DATE AS day,
      COUNT(*)::INT AS redemptions,
      COALESCE(SUM(COALESCE(o.coupon_discount_total, cr.discount_amount)), 0)::NUMERIC(12,2) AS discount_total
    FROM coupon_redemption cr
    JOIN coupon c ON c.id = cr.coupon_id
    LEFT JOIN customer_order o ON o.id = cr.order_id
    ${
      scopeRedemption.conditions.length
        ? `WHERE ${scopeRedemption.conditions.join(" AND ")} AND`
        : "WHERE"
    }
      COALESCE(cr.is_void, FALSE) = FALSE
      AND o.status IN ('delivered', 'delivered_by_courier', 'received_by_customer', 'completed')
      AND
      cr.redeemed_at >= (NOW() - ($${timelineDaysParam} * INTERVAL '1 day'))
    GROUP BY 1
    ORDER BY 1 DESC`;
  const timelineResult = await q(timelineQuery, timelineParams);

  const totalUses = Number(summary.total_uses || 0);
  const boundedSlots = Number(summary.bounded_slots || 0);
  const usageRate = boundedSlots > 0 ? (totalUses / boundedSlots) * 100 : null;
  const totalDiscountGiven = timelineResult.rows.reduce(
    (sum, row) => sum + Number(row.discount_total || 0),
    0,
  );
  const avgDiscountPerUse = totalUses > 0 ? totalDiscountGiven / totalUses : 0;

  return {
    totals: {
      totalCoupons: Number(summary.total_coupons || 0),
      activeCoupons: Number(summary.active_coupons || 0),
      inactiveCoupons: Number(summary.inactive_coupons || 0),
      expiredCoupons: Number(summary.expired_coupons || 0),
      scheduledCoupons: Number(summary.scheduled_coupons || 0),
      totalUses,
      totalDiscountGiven,
      grossSalesTotal: Number(summary.gross_sales_total || 0),
      netSalesTotal: Number(summary.net_sales_total || 0),
      couponDiscountTotal: Number(summary.coupon_discount_total || 0),
    },
    performance: {
      usageRate,
      avgDiscountPerUse,
      boundedSlots,
      avgOrderValue: Number(summary.avg_order_value || 0),
    },
    topCoupons: topResult.rows,
    timeline: timelineResult.rows,
    windowDays: normalizedDays,
  };
}

export async function findOwnerMerchantByUserId(ownerUserId) {
  const r = await q(
    `SELECT id, owner_user_id
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function findValidCouponByIdOrCode(
  { couponId = null, code = null },
  { customerId, merchantId, orderTotal }
) {
  const normalizedCouponId = Number(couponId || 0);
  const normalizedCode =
    typeof code === "string" && code.trim().length > 0 ? code.trim() : null;

  if (normalizedCouponId > 0) {
    const r = await q(
      `SELECT c.*
       FROM coupon c
       LEFT JOIN merchant target_merchant ON target_merchant.id = $2
       WHERE c.id = $1
         AND c.is_active = TRUE
         AND (c.valid_from  IS NULL OR c.valid_from  <= NOW())
         AND (c.valid_until IS NULL OR c.valid_until >= NOW())
         AND (c.max_uses    IS NULL OR c.uses_count < c.max_uses)
         AND (
           (c.scope_kind = 'global' AND c.merchant_id IS NULL AND c.company_id IS NULL)
           OR (c.scope_kind = 'merchant' AND c.merchant_id = $2)
           OR (
             c.scope_kind = 'company'
             AND target_merchant.company_id IS NOT NULL
             AND c.company_id = target_merchant.company_id
             AND (
               c.company_applies_to_all_branches = TRUE
               OR EXISTS (
                 SELECT 1
                 FROM company_coupon_target cct
                 WHERE cct.coupon_id = c.id
                   AND cct.merchant_id = $2
               )
             )
           )
         )
         AND (c.min_order_total = 0  OR $3 >= c.min_order_total)
         AND NOT EXISTS (
           SELECT 1 FROM coupon_redemption cr
           WHERE cr.coupon_id = c.id
             AND cr.customer_id = $4
             AND COALESCE(cr.is_void, FALSE) = FALSE
         )
       LIMIT 1`,
      [normalizedCouponId, merchantId || null, Number(orderTotal || 0), customerId]
    );
    return r.rows[0] || null;
  }

  if (!normalizedCode) return null;
  return findValidCoupon(normalizedCode, { customerId, merchantId, orderTotal });
}

export async function toggleCouponActive(couponId, isActive) {
  const r = await q(
    `UPDATE coupon SET is_active = $1 WHERE id = $2`,
    [isActive, Number(couponId)]
  );
  return r.rowCount > 0;
}

export async function deleteCoupon(couponId) {
  const r = await q(`DELETE FROM coupon WHERE id = $1`, [Number(couponId)]);
  return r.rowCount > 0;
}

export async function toggleCouponActiveForOwner({
  couponId,
  isActive,
  ownerUserId,
}) {
  const r = await q(
    `UPDATE coupon c
     SET is_active = $1
     FROM merchant m
     WHERE c.id = $2
       AND c.merchant_id = m.id
       AND m.owner_user_id = $3`,
    [isActive, Number(couponId), Number(ownerUserId)]
  );
  return r.rowCount > 0;
}

export async function deleteCouponForOwner({ couponId, ownerUserId }) {
  const r = await q(
    `DELETE FROM coupon c
     USING merchant m
     WHERE c.id = $1
       AND c.merchant_id = m.id
       AND m.owner_user_id = $2`,
    [Number(couponId), Number(ownerUserId)]
  );
  return r.rowCount > 0;
}

function buildCouponScope({ alias, merchantId, includeGlobal }) {
  const conditions = [];
  const params = [];
  let nextParamIndex = 1;
  const normalizedMerchantId = Number(merchantId || 0);

  if (normalizedMerchantId > 0) {
    if (includeGlobal) {
      conditions.push(
        `(${alias}.merchant_id = $${nextParamIndex} OR ${alias}.merchant_id IS NULL)`,
      );
    } else {
      conditions.push(`${alias}.merchant_id = $${nextParamIndex}`);
    }
    params.push(normalizedMerchantId);
    nextParamIndex += 1;
  }

  return { conditions, params, nextParamIndex };
}

