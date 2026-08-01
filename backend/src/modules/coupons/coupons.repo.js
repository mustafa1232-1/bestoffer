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

export function couponLifecycleStatusSql(alias = "c") {
  return `CASE
    WHEN ${alias}.is_active = FALSE THEN 'inactive'
    WHEN ${alias}.valid_from IS NOT NULL AND ${alias}.valid_from > NOW() THEN 'scheduled'
    WHEN ${alias}.valid_until IS NOT NULL AND ${alias}.valid_until < NOW() THEN 'expired'
    WHEN ${alias}.max_uses IS NOT NULL AND ${alias}.max_uses > 0 AND ${alias}.uses_count >= ${alias}.max_uses THEN 'exhausted'
    ELSE 'active'
  END`;
}

export function resolveCouponLifecycleStatus(coupon, now = new Date()) {
  if (!coupon) return "missing";

  const nowTs = now instanceof Date ? now.getTime() : new Date(now).getTime();
  const validFrom = coupon.valid_from ? new Date(coupon.valid_from) : null;
  const validUntil = coupon.valid_until ? new Date(coupon.valid_until) : null;
  const usesCount = Number(coupon.uses_count || 0);
  const maxUses = Number(coupon.max_uses || 0);

  if (coupon.is_active !== true) return "inactive";
  if (Number.isFinite(validFrom?.getTime()) && validFrom.getTime() > nowTs) {
    return "scheduled";
  }
  if (Number.isFinite(validUntil?.getTime()) && validUntil.getTime() < nowTs) {
    return "expired";
  }
  if (maxUses > 0 && usesCount >= maxUses) {
    return "exhausted";
  }
  return "active";
}

export function resolveCouponValidationReason(
  coupon,
  { customerId, merchantId, orderTotal } = {},
  now = new Date()
) {
  if (!coupon) return "COUPON_NOT_FOUND";

  const lifecycleStatus = resolveCouponLifecycleStatus(coupon, now);
  switch (lifecycleStatus) {
    case "inactive":
      return "COUPON_INACTIVE";
    case "scheduled":
      return "COUPON_NOT_STARTED";
    case "expired":
      return "COUPON_EXPIRED";
    case "exhausted":
      return "COUPON_TOTAL_LIMIT_REACHED";
    default:
      break;
  }

  const normalizedMerchantId = Number(merchantId || 0);
  if (coupon.scope_kind === "merchant") {
    if (normalizedMerchantId <= 0 || Number(coupon.merchant_id || 0) !== normalizedMerchantId) {
      return "COUPON_NOT_TARGETED";
    }
  } else if (coupon.scope_kind === "company") {
    if (normalizedMerchantId <= 0) return "COUPON_NOT_TARGETED";

    const couponCompanyId = Number(coupon.company_id || 0);
    const targetCompanyId = Number(coupon.target_merchant_company_id || 0);
    if (couponCompanyId <= 0 || targetCompanyId <= 0 || couponCompanyId !== targetCompanyId) {
      return "COUPON_NOT_TARGETED";
    }

    if (coupon.company_applies_to_all_branches !== true && coupon.matches_company_target !== true) {
      return "COUPON_NOT_TARGETED";
    }
  }

  if (Number(orderTotal || 0) < Number(coupon.min_order_total || 0)) {
    return "COUPON_INVALID_OR_EXPIRED";
  }

  if (coupon.customer_redeemed === true) {
    return "COUPON_USER_LIMIT_REACHED";
  }

  return null;
}

async function loadCouponValidationCandidateByCode(code, { customerId, merchantId }) {
  const r = await q(
    `SELECT
       c.*,
       target_merchant.company_id AS target_merchant_company_id,
       CASE
         WHEN c.scope_kind = 'global' AND c.merchant_id IS NULL AND c.company_id IS NULL THEN TRUE
         WHEN c.scope_kind = 'merchant' AND c.merchant_id = $2 THEN TRUE
         WHEN c.scope_kind = 'company'
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
         THEN TRUE
         ELSE FALSE
       END AS matches_company_target,
       EXISTS (
         SELECT 1
         FROM coupon_redemption cr
         WHERE cr.coupon_id = c.id
           AND cr.customer_id = $3
           AND COALESCE(cr.is_void, FALSE) = FALSE
       ) AS customer_redeemed
     FROM coupon c
      LEFT JOIN merchant target_merchant ON target_merchant.id = $2::INT
      WHERE UPPER(c.code) = UPPER($1)
     LIMIT 1`,
    [code, merchantId || null, customerId]
  );
  return r.rows[0] || null;
}

async function loadCouponValidationCandidateById(couponId, { customerId, merchantId }) {
  const r = await q(
    `SELECT
       c.*,
       target_merchant.company_id AS target_merchant_company_id,
       CASE
         WHEN c.scope_kind = 'global' AND c.merchant_id IS NULL AND c.company_id IS NULL THEN TRUE
         WHEN c.scope_kind = 'merchant' AND c.merchant_id = $2 THEN TRUE
         WHEN c.scope_kind = 'company'
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
         THEN TRUE
         ELSE FALSE
       END AS matches_company_target,
       EXISTS (
         SELECT 1
         FROM coupon_redemption cr
         WHERE cr.coupon_id = c.id
           AND cr.customer_id = $3
           AND COALESCE(cr.is_void, FALSE) = FALSE
       ) AS customer_redeemed
     FROM coupon c
      LEFT JOIN merchant target_merchant ON target_merchant.id = $2::INT
      WHERE c.id = $1
      LIMIT 1`,
    [Number(couponId), merchantId || null, customerId]
  );
  return r.rows[0] || null;
}

export async function validateCouponByCode(
  code,
  { customerId, merchantId, orderTotal }
) {
  const coupon = await loadCouponValidationCandidateByCode(code, {
    customerId,
    merchantId,
    orderTotal,
  });
  const reasonCode = resolveCouponValidationReason(coupon, {
    customerId,
    merchantId,
    orderTotal,
  });
  return {
    coupon: reasonCode == null ? coupon : null,
    reasonCode,
  };
}

export async function validateCouponByIdOrCode(
  { couponId = null, code = null },
  { customerId, merchantId, orderTotal }
) {
  const normalizedCouponId = Number(couponId || 0);
  const normalizedCode =
    typeof code === "string" && code.trim().length > 0 ? code.trim() : null;

  if (normalizedCouponId > 0) {
    const coupon = await loadCouponValidationCandidateById(normalizedCouponId, {
      customerId,
      merchantId,
      orderTotal,
    });
    const reasonCode = resolveCouponValidationReason(coupon, {
      customerId,
      merchantId,
      orderTotal,
    });
    return {
      coupon: reasonCode == null ? coupon : null,
      reasonCode,
    };
  }

  if (!normalizedCode) {
    return { coupon: null, reasonCode: "COUPON_NOT_FOUND" };
  }

  return validateCouponByCode(normalizedCode, {
    customerId,
    merchantId,
    orderTotal,
  });
}

/**
 * Look up a coupon by its code and validate it's usable:
 * - active, within valid dates, not exceeded max_uses
 * - optionally scoped to a merchant
 * - customer hasn't already used it
 * Returns the coupon row or null.
 */
export async function findValidCoupon(code, { customerId, merchantId, orderTotal }) {
  const result = await validateCouponByCode(code, {
    customerId,
    merchantId,
    orderTotal,
  });
  return result.coupon;
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
       ${couponLifecycleStatusSql("c")} AS coupon_status,
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
  return r.rows.map((row) => ({
    ...row,
    coupon_status: row.coupon_status || "unknown",
  }));
}

// ── Admin CRUD ────────────────────────────────────────────────────────────────

export async function createCoupon({
  code, description, discountType, discountValue, minOrderTotal,
  maxUses, merchantId, validFrom, validUntil, createdBy, agentUserId = null,
  agentCommissionSharePercent = null,
}) {
  // scope_kind MUST be set explicitly (see resolveCouponScopeKind). The column
  // defaults to 'merchant', so omitting it made global coupons (no merchant_id)
  // default to 'merchant' with a NULL merchant_id — which the validation query
  // can never match, making every global coupon report as invalid.
  const resolvedMerchantId = merchantId ? Number(merchantId) : null;
  const scopeKind = resolveCouponScopeKind({ merchantId: resolvedMerchantId });
  const resolvedAgentUserId =
    agentUserId != null && Number(agentUserId) > 0 ? Number(agentUserId) : null;
  // Only agent coupons carry an earning share; clamp to [0, 100].
  const resolvedShare =
    resolvedAgentUserId != null && agentCommissionSharePercent != null
      ? Math.max(0, Math.min(100, Number(agentCommissionSharePercent)))
      : null;
  const r = await q(
    `INSERT INTO coupon
       (code, description, discount_type, discount_value, min_order_total,
        max_uses, merchant_id, scope_kind, valid_from, valid_until, created_by,
        agent_user_id, agent_commission_share_percent)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
     RETURNING *`,
    [
      code.toUpperCase().trim(), description || null, discountType,
      Number(discountValue), Number(minOrderTotal || 0),
      maxUses ? Number(maxUses) : null,
      resolvedMerchantId,
      scopeKind,
      validFrom || null, validUntil || null, createdBy,
      resolvedAgentUserId,
      resolvedShare,
    ]
  );
  return r.rows[0];
}

/**
 * Every agent (employee) coupon owned by a user — even those with no redemptions
 * yet — so the employee portal can show the coupon code + earning share.
 */
export async function listAgentCouponsForUser(agentUserId) {
  const r = await q(
    `SELECT
       id,
       code,
       discount_type,
       discount_value,
       is_active,
       COALESCE(agent_commission_share_percent, 25) AS share_percent,
       created_at
     FROM coupon
     WHERE agent_user_id = $1
     ORDER BY created_at DESC, id DESC`,
    [Number(agentUserId)]
  );
  return r.rows;
}

/**
 * The redeemed, COMPLETED orders behind agent coupons, with each order's full
 * row and its merchant billing profile — enough to recompute the company
 * commission per order via `computeOrderFinancialSnapshot`. Only completed
 * orders count (an employee earns once the order is actually delivered, never on
 * pending/cancelled ones). Pass an agentUserId to scope to one employee, or omit
 * for every agent coupon (admin report).
 */
export async function listAgentCouponEarningRows({ agentUserId = null } = {}) {
  const params = [];
  let filter = "";
  if (agentUserId != null && Number(agentUserId) > 0) {
    params.push(Number(agentUserId));
    filter = `AND c.agent_user_id = $${params.length}`;
  }
  const r = await q(
    `SELECT
       c.id                                       AS coupon_id,
       c.agent_user_id                            AS agent_user_id,
       COALESCE(c.agent_commission_share_percent, 25) AS share_percent,
       cr.order_id                                AS order_id,
       cr.customer_id                             AS customer_id,
       cr.redeemed_at                             AS redeemed_at,
       to_jsonb(o.*)                              AS order_json,
       to_jsonb(bp.*)                             AS profile_json
     FROM coupon c
     JOIN coupon_redemption cr
       ON cr.coupon_id = c.id
      AND COALESCE(cr.is_void, FALSE) = FALSE
     JOIN customer_order o
       ON o.id = cr.order_id
      AND o.status IN ('delivered','delivered_by_courier','received_by_customer','completed')
     LEFT JOIN merchant_billing_profile bp
       ON bp.merchant_id = o.merchant_id
     WHERE c.agent_user_id IS NOT NULL
       ${filter}
     ORDER BY cr.redeemed_at DESC
     LIMIT 1000`,
    params
  );
  return r.rows;
}

/**
 * Update a coupon's discount (type + value). Used by the admin to attach or
 * change the discount on an employee referral coupon (0 = attribution only).
 */
export async function updateCouponDiscount(couponId, { discountType, discountValue }) {
  const r = await q(
    `UPDATE coupon
        SET discount_type = $2,
            discount_value = $3,
            updated_at = NOW()
      WHERE id = $1
      RETURNING *`,
    [Number(couponId), discountType, Number(discountValue)]
  );
  return r.rows[0] || null;
}

/**
 * Admin report: every employee referral coupon (agent_user_id set) with the
 * employee's identity and its attribution stats — how many customers/orders came
 * through it, and the total discount granted.
 */
export async function listAgentReferralCoupons() {
  const r = await q(
    `SELECT
       c.id,
       c.code,
       c.discount_type,
       c.discount_value,
       c.is_active,
       c.created_at,
       c.agent_user_id,
       c.agent_commission_share_percent,
       u.full_name  AS agent_name,
       u.phone      AS agent_phone,
       u.role       AS agent_role,
       COALESCE(rc.redemptions, 0)        AS redemptions,
       COALESCE(rc.unique_customers, 0)   AS unique_customers,
       COALESCE(rc.total_discount, 0)     AS total_discount
     FROM coupon c
     JOIN app_user u ON u.id = c.agent_user_id
     LEFT JOIN (
       SELECT
         coupon_id,
         COUNT(*) FILTER (WHERE COALESCE(is_void, FALSE) = FALSE)          AS redemptions,
         COUNT(DISTINCT customer_id) FILTER (WHERE COALESCE(is_void, FALSE) = FALSE) AS unique_customers,
         COALESCE(SUM(discount_amount) FILTER (WHERE COALESCE(is_void, FALSE) = FALSE), 0) AS total_discount
       FROM coupon_redemption
       GROUP BY coupon_id
     ) rc ON rc.coupon_id = c.id
     WHERE c.agent_user_id IS NOT NULL
     ORDER BY COALESCE(rc.redemptions, 0) DESC, c.created_at DESC`
  );
  return r.rows;
}

/**
 * The customers + orders that redeemed a specific agent coupon (attribution
 * detail for one employee).
 */
export async function listAgentCouponRedemptions(couponId, { limit = 200 } = {}) {
  const r = await q(
    `SELECT
       cr.customer_id,
       cu.full_name AS customer_name,
       cu.phone     AS customer_phone,
       cr.order_id,
       cr.discount_amount,
       cr.redeemed_at AS created_at
     FROM coupon_redemption cr
     LEFT JOIN app_user cu ON cu.id = cr.customer_id
     WHERE cr.coupon_id = $1
       AND COALESCE(cr.is_void, FALSE) = FALSE
     ORDER BY cr.redeemed_at DESC
     LIMIT $2`,
    [Number(couponId), Math.max(1, Math.min(500, Number(limit) || 200))]
  );
  return r.rows;
}

export async function getCouponById(couponId) {
  const r = await q(`SELECT * FROM coupon WHERE id = $1`, [Number(couponId)]);
  return r.rows[0] || null;
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
    conditions.push(`${couponLifecycleStatusSql("c")} = 'active'`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
  params.push(limit, offset);

  const r = await q(
    `SELECT
       c.*,
       ${couponLifecycleStatusSql("c")} AS coupon_status,
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
  return r.rows.map((row) => ({
    ...row,
    coupon_status: row.coupon_status || "unknown",
  }));
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
      COUNT(*) FILTER (WHERE ${couponLifecycleStatusSql("c")} = 'active')::INT AS active_coupons,
      COUNT(*) FILTER (WHERE ${couponLifecycleStatusSql("c")} = 'inactive')::INT AS inactive_coupons,
      COUNT(*) FILTER (WHERE ${couponLifecycleStatusSql("c")} = 'expired')::INT AS expired_coupons,
      COUNT(*) FILTER (WHERE ${couponLifecycleStatusSql("c")} = 'scheduled')::INT AS scheduled_coupons,
      COUNT(*) FILTER (WHERE ${couponLifecycleStatusSql("c")} = 'exhausted')::INT AS exhausted_coupons,
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
      exhaustedCoupons: Number(summary.exhausted_coupons || 0),
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
  const result = await validateCouponByIdOrCode(
    { couponId, code },
    { customerId, merchantId, orderTotal }
  );
  return result.coupon;
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

