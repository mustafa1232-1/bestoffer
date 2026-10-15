import { pool, q } from "../../config/db.js";

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
  if (
    coupon.target_user_id != null &&
    Number(coupon.target_user_id) !== Number(customerId || 0)
  ) {
    return "COUPON_NOT_TARGETED";
  }
  if (
    Number(coupon.max_uses_per_user || 0) > 0 &&
    Number(coupon.customer_redemption_count || 0) >=
      Number(coupon.max_uses_per_user)
  ) {
    return "COUPON_ALREADY_USED";
  }
  if (
    coupon.new_customers_only === true &&
    (!coupon.customer_created_at ||
      new Date(coupon.customer_created_at).getTime() <
        new Date(coupon.valid_from || coupon.created_at).getTime())
  ) {
    return "COUPON_NOT_ELIGIBLE";
  }
  if (coupon.new_customers_only === true && coupon.customer_redeemed === true) {
    return "COUPON_ALREADY_USED";
  }
  if (!["shopping", "all"].includes(coupon.surface_scope || "shopping")) {
    return "COUPON_NOT_TARGETED";
  }
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

  return null;
}

async function loadCouponValidationCandidateByCode(code, { customerId, merchantId }) {
  const r = await q(
    `SELECT
       c.*,
       (SELECT created_at FROM app_user WHERE id = $3) AS customer_created_at,
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
       COUNT(cr_customer.id)::INT AS customer_redemption_count,
       (COUNT(cr_customer.id) > 0) AS customer_redeemed
     FROM coupon c
      LEFT JOIN merchant target_merchant ON target_merchant.id = $2::INT
      LEFT JOIN coupon_redemption cr_customer
        ON cr_customer.coupon_id = c.id
       AND cr_customer.customer_id = $3
       AND COALESCE(cr_customer.is_void, FALSE) = FALSE
      WHERE UPPER(c.code) = UPPER($1)
       GROUP BY c.id, target_merchant.company_id
     LIMIT 1`,
    [code, merchantId || null, customerId]
  );
  return r.rows[0] || null;
}

async function loadCouponValidationCandidateById(couponId, { customerId, merchantId }) {
  const r = await q(
    `SELECT
       c.*,
       (SELECT created_at FROM app_user WHERE id = $3) AS customer_created_at,
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
       COUNT(cr_customer.id)::INT AS customer_redemption_count,
       (COUNT(cr_customer.id) > 0) AS customer_redeemed
     FROM coupon c
      LEFT JOIN merchant target_merchant ON target_merchant.id = $2::INT
      LEFT JOIN coupon_redemption cr_customer
        ON cr_customer.coupon_id = c.id
       AND cr_customer.customer_id = $3
       AND COALESCE(cr_customer.is_void, FALSE) = FALSE
      WHERE c.id = $1
        GROUP BY c.id, target_merchant.company_id
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
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const existing = await client.query(
      `SELECT id
       FROM coupon_redemption
       WHERE coupon_id = $1
         AND order_id = $2
         AND COALESCE(is_void, FALSE) = FALSE
       LIMIT 1
       FOR UPDATE`,
      [Number(couponId), orderId || null]
    );
    if (!existing.rows[0]) {
      const couponLock = await client.query(
        `SELECT max_uses_per_user
         FROM coupon
         WHERE id = $1
         FOR UPDATE`,
        [Number(couponId)],
      );
      const maxUsesPerUser = Number(
        couponLock.rows[0]?.max_uses_per_user || 0,
      );
      if (maxUsesPerUser > 0) {
        const customerUses = await client.query(
          `SELECT COUNT(*)::INT AS uses
           FROM coupon_redemption
           WHERE coupon_id = $1
             AND customer_id = $2
             AND COALESCE(is_void, FALSE) = FALSE`,
          [Number(couponId), Number(customerId)],
        );
        if (Number(customerUses.rows[0]?.uses || 0) >= maxUsesPerUser) {
          throw referralError("COUPON_ALREADY_USED");
        }
      }
      const locked = await client.query(
        `UPDATE coupon
         SET uses_count = COALESCE(uses_count, 0) + 1
         WHERE id = $1
           AND is_active = TRUE
           AND (valid_from IS NULL OR valid_from <= NOW())
           AND (valid_until IS NULL OR valid_until >= NOW())
           AND (max_uses IS NULL OR max_uses <= 0 OR COALESCE(uses_count, 0) < max_uses)
         RETURNING id`,
        [Number(couponId)]
      );
      if (!locked.rows[0]) {
        const err = new Error("COUPON_INVALID_OR_EXPIRED");
        err.status = 409;
        throw err;
      }
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
        [couponId, customerId, orderId || null, discountAmount]
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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
       LEFT JOIN influencer_coupon_campaign icc ON icc.coupon_id = c.id
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
         AND icc.id IS NULL
       AND (c.valid_from IS NULL OR c.valid_from <= NOW())
       AND (c.valid_until IS NULL OR c.valid_until >= NOW())
       AND (c.max_uses IS NULL OR c.max_uses <= 0 OR c.uses_count < c.max_uses)
       AND (
         $3::bigint IS NULL
         OR c.max_uses_per_user IS NULL
         OR c.max_uses_per_user <= 0
         OR (
           SELECT COUNT(*)
           FROM coupon_redemption cr_customer
           WHERE cr_customer.coupon_id = c.id
             AND cr_customer.customer_id = $3
             AND COALESCE(cr_customer.is_void, FALSE) = FALSE
         ) < c.max_uses_per_user
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
         $1::bigint IS NULL
         OR c.scope_kind = 'global'
         OR (c.scope_kind = 'merchant' AND c.merchant_id = $1)
         OR (
           c.scope_kind = 'company'
           AND c.company_id IS NOT NULL
           AND (
             (
               c.company_applies_to_all_branches = TRUE
               AND EXISTS (
                 SELECT 1
                 FROM merchant m_scope
                 WHERE m_scope.id = $1
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
                   AND cct_scope.merchant_id = $1
                   AND m_scope_target.is_approved = TRUE
                   AND COALESCE(m_scope_target.is_disabled, FALSE) = FALSE
               )
             )
           )
         )
       )
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT $2`,
     [safeMerchantId, safeLimit, safeCustomerId]
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
  surfaceScope = "shopping",
  targetUserId = null,
  popupEnabled = false,
  popupTitle = null,
  popupMessage = null,
  newCustomersOnly = false,
  maxUsesPerUser = null,
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
        agent_user_id, agent_commission_share_percent, surface_scope,
        target_user_id, popup_enabled, popup_title, popup_message,
        new_customers_only, max_uses_per_user)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
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
      ["shopping", "taxi", "services", "all"].includes(surfaceScope)
        ? surfaceScope
        : "shopping",
      Number(targetUserId || 0) > 0 ? Number(targetUserId) : null,
      popupEnabled === true,
      popupTitle || null,
      popupMessage || null,
      newCustomersOnly === true,
      Number(maxUsesPerUser || 0) > 0 ? Number(maxUsesPerUser) : null,
    ]
  );
  const created = r.rows[0];
  if (created && ["taxi", "all"].includes(surfaceScope)) {
    const taxiCouponR = await q(
      `INSERT INTO taxi_coupon (
         code, title, description, is_active, valid_from, valid_until,
         max_total_uses, max_uses_per_user, apply_whole_app,
         created_by_admin_user_id, created_at, updated_at
       ) VALUES ($1,$2,$3,TRUE,$4,$5,$6,1,$7,$8,NOW(),NOW())
       ON CONFLICT (code) DO UPDATE SET
         title = EXCLUDED.title,
         description = EXCLUDED.description,
         is_active = TRUE,
         valid_from = EXCLUDED.valid_from,
         valid_until = EXCLUDED.valid_until,
         max_total_uses = EXCLUDED.max_total_uses,
         max_uses_per_user = 1,
         apply_whole_app = EXCLUDED.apply_whole_app,
         updated_at = NOW()
       RETURNING id`,
      [
        created.code,
        popupTitle || description || created.code,
        popupMessage || description || null,
        validFrom || null,
        validUntil || null,
        maxUses ? Number(maxUses) : null,
        Number(targetUserId || 0) <= 0,
        Number(createdBy),
      ],
    );
    const taxiCouponId = Number(taxiCouponR.rows[0]?.id || 0);
    if (taxiCouponId > 0) {
      await q(`DELETE FROM taxi_coupon_discount_tier WHERE coupon_id = $1`, [taxiCouponId]);
      await q(
        `INSERT INTO taxi_coupon_discount_tier (
           coupon_id, use_index, discount_type, discount_value
         ) VALUES ($1,1,$2,$3)`,
        [
          taxiCouponId,
          discountType === "percent" ? "percent" : "amount",
          Math.max(1, Math.round(Number(discountValue))),
        ],
      );
      await q(`DELETE FROM taxi_coupon_target_user WHERE coupon_id = $1`, [taxiCouponId]);
      if (Number(targetUserId || 0) > 0) {
        await q(
          `INSERT INTO taxi_coupon_target_user (coupon_id, user_id)
           VALUES ($1,$2)
           ON CONFLICT (coupon_id, user_id) DO NOTHING`,
          [taxiCouponId, Number(targetUserId)],
        );
      }
    }
  }
  return created;
}

export async function getPendingCouponPopupForUser(userId) {
  const r = await q(
    `SELECT c.*
     FROM coupon c
     JOIN app_user u ON u.id = $1
     LEFT JOIN coupon_popup_delivery d
       ON d.coupon_id = c.id AND d.user_id = u.id
     WHERE c.popup_enabled = TRUE
       AND c.is_active = TRUE
       AND (c.valid_from IS NULL OR c.valid_from <= NOW())
       AND (c.valid_until IS NULL OR c.valid_until >= NOW())
       AND (c.max_uses IS NULL OR c.max_uses <= 0 OR COALESCE(c.uses_count, 0) < c.max_uses)
       AND (c.target_user_id IS NULL OR c.target_user_id = u.id)
       AND (c.new_customers_only = FALSE OR u.created_at >= COALESCE(c.valid_from, c.created_at))
       AND NOT EXISTS (
         SELECT 1
         FROM coupon_redemption cr
         WHERE cr.coupon_id = c.id
           AND cr.customer_id = u.id
           AND COALESCE(cr.is_void, FALSE) = FALSE
       )
       AND d.acknowledged_at IS NULL
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT 1`,
    [Number(userId)],
  );
  const coupon = r.rows[0] || null;
  if (!coupon) return null;
  await q(
    `INSERT INTO coupon_popup_delivery (coupon_id, user_id)
     VALUES ($1,$2)
     ON CONFLICT (coupon_id, user_id) DO NOTHING`,
    [Number(coupon.id), Number(userId)],
  );
  return coupon;
}

export async function acknowledgeCouponPopupForUser({ couponId, userId }) {
  const r = await q(
    `UPDATE coupon_popup_delivery
     SET acknowledged_at = COALESCE(acknowledged_at, NOW())
     WHERE coupon_id = $1 AND user_id = $2
     RETURNING id`,
    [Number(couponId), Number(userId)],
  );
  return Boolean(r.rows[0]);
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

// ── Influencer referral campaigns ───────────────────────────────────────────

function referralError(code, status = 409) {
  const error = new Error(code);
  error.status = status;
  return error;
}

export async function createInfluencerProfile({
  trackingCode,
  displayName,
  handle = null,
  contactPhone = null,
  notes = null,
  rewardPerQualifiedUser = 0,
  qualificationRule = "first_completed_order",
  createdByUserId,
}) {
  const result = await q(
    `INSERT INTO influencer_profile (
       tracking_code, display_name, handle, contact_phone, notes,
       reward_per_qualified_user, qualification_rule, created_by_user_id
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING *`,
    [
      String(trackingCode).trim().toUpperCase(),
      String(displayName).trim(),
      handle || null,
      contactPhone || null,
      notes || null,
      Number(rewardPerQualifiedUser || 0),
      qualificationRule,
      Number(createdByUserId),
    ],
  );
  return result.rows[0] || null;
}

export async function createInfluencerCoupon({
  influencerId,
  code,
  label = null,
  discountType = "percent",
  discountValue = 0,
  minOrderTotal = 0,
  maxUses = null,
  validFrom = null,
  validUntil = null,
  createdByUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const profileResult = await client.query(
      `SELECT id, display_name, tracking_code
       FROM influencer_profile
       WHERE id = $1
       LIMIT 1
       FOR UPDATE`,
      [Number(influencerId)],
    );
    const profile = profileResult.rows[0] || null;
    if (!profile) throw referralError("INFLUENCER_NOT_FOUND", 404);

    const couponResult = await client.query(
      `INSERT INTO coupon (
         code, description, discount_type, discount_value, min_order_total,
         max_uses, max_uses_per_user, merchant_id, scope_kind, valid_from,
         valid_until, is_active, created_by, surface_scope
       ) VALUES ($1,$2,$3,$4,$5,$6,1,NULL,'global',$7,$8,TRUE,$9,'shopping')
       RETURNING *`,
      [
        String(code).trim().toUpperCase(),
        label || `Influencer marketing coupon: ${profile.display_name}`,
        discountType,
        Number(discountValue || 0),
        Number(minOrderTotal || 0),
        maxUses == null ? null : Number(maxUses),
        validFrom || null,
        validUntil || null,
        Number(createdByUserId),
      ],
    );
    const coupon = couponResult.rows[0];
    const campaignResult = await client.query(
      `INSERT INTO influencer_coupon_campaign (
         influencer_id, coupon_id, label, created_by_user_id
       ) VALUES ($1,$2,$3,$4)
       RETURNING *`,
      [
        Number(influencerId),
        Number(coupon.id),
        label || null,
        Number(createdByUserId),
      ],
    );
    await client.query("COMMIT");
    return { ...campaignResult.rows[0], coupon, profile };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

export async function claimInfluencerReferral({
  code,
  userId,
  deviceFingerprint,
  authSessionId = null,
  transactionClient = null,
}) {
  const ownsTransaction = transactionClient == null;
  const client = transactionClient || (await pool.connect());
  try {
    if (ownsTransaction) await client.query("BEGIN");
    const influencerResult = await client.query(
      `SELECT *
       FROM influencer_profile
       WHERE tracking_code = UPPER($1)
       LIMIT 1
       FOR UPDATE`,
      [String(code || "").trim()],
    );
    const influencer = influencerResult.rows[0] || null;
    if (!influencer) throw referralError("INFLUENCER_CODE_NOT_FOUND", 404);
    if (influencer.is_active !== true) {
      throw referralError("REFERRAL_CAMPAIGN_INACTIVE");
    }

    const existingUserResult = await client.query(
      `SELECT ira.*, ip.tracking_code, ip.display_name
       FROM influencer_referral_attribution ira
       JOIN influencer_profile ip ON ip.id = ira.influencer_id
       WHERE ira.user_id = $1
       LIMIT 1
       FOR UPDATE OF ira`,
      [Number(userId)],
    );
    const existingUser = existingUserResult.rows[0] || null;
    if (existingUser) {
      if (Number(existingUser.influencer_id) !== Number(influencer.id)) {
        throw referralError("REFERRAL_ATTRIBUTION_LOCKED");
      }
      if (ownsTransaction) await client.query("COMMIT");
      return { attribution: existingUser, influencer, created: false };
    }

    const priorCompletedOrderResult = await client.query(
      `SELECT 1
       FROM customer_order
       WHERE customer_user_id = $1
         AND status IN ('delivered','delivered_by_courier','received_by_customer','completed')
       LIMIT 1`,
      [Number(userId)],
    );
    if (priorCompletedOrderResult.rows[0]) {
      throw referralError("REFERRAL_NEW_CUSTOMERS_ONLY");
    }

    const existingDeviceResult = await client.query(
      `SELECT user_id, influencer_id
       FROM influencer_referral_attribution
       WHERE device_fingerprint = $1
       LIMIT 1
       FOR UPDATE`,
      [String(deviceFingerprint).trim()],
    );
    if (existingDeviceResult.rows[0]) {
      throw referralError("REFERRAL_DEVICE_ALREADY_ATTRIBUTED");
    }

    let inserted;
    try {
      const insertedResult = await client.query(
        `INSERT INTO influencer_referral_attribution (
           influencer_id, user_id, device_fingerprint, auth_session_id
         ) VALUES ($1,$2,$3,$4)
         RETURNING *`,
        [
          Number(influencer.id),
          Number(userId),
          String(deviceFingerprint).trim(),
          authSessionId == null ? null : Number(authSessionId),
        ],
      );
      inserted = insertedResult.rows[0];
    } catch (error) {
      if (String(error?.code || "") === "23505") {
        if (
          String(error?.constraint || "") ===
          "influencer_referral_attribution_device_unique"
        ) {
          throw referralError("REFERRAL_DEVICE_ALREADY_ATTRIBUTED");
        }
        throw referralError("REFERRAL_ATTRIBUTION_LOCKED");
      }
      throw error;
    }

    if (ownsTransaction) await client.query("COMMIT");
    return { attribution: inserted, influencer, created: true };
  } catch (error) {
    if (ownsTransaction) await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    if (ownsTransaction) client.release();
  }
}

export async function listInfluencerProfiles() {
  const result = await q(
    `SELECT
       ip.*,
       COALESCE(stats.attributed_users, 0)::INT AS attributed_users,
       COALESCE(stats.converted_users, 0)::INT AS converted_users,
       COALESCE(stats.completed_orders, 0)::INT AS completed_orders,
       COALESCE(stats.total_spent, 0)::NUMERIC AS total_spent,
       COALESCE(coupon_stats.coupons, '[]'::jsonb) AS coupons
     FROM influencer_profile ip
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*)::INT AS attributed_users,
          COUNT(*) FILTER (WHERE customer_orders.completed_orders > 0)::INT AS converted_users,
          COALESCE(SUM(customer_orders.completed_orders), 0)::INT AS completed_orders,
          COALESCE(SUM(customer_orders.total_spent), 0)::NUMERIC AS total_spent
       FROM influencer_referral_attribution ira
       LEFT JOIN LATERAL (
         SELECT
            COUNT(*)::INT AS completed_orders,
            COALESCE(SUM(o.total_amount), 0)::NUMERIC AS total_spent
         FROM customer_order o
         WHERE o.customer_user_id = ira.user_id
           AND o.created_at >= ira.claimed_at
           AND o.status IN ('delivered','delivered_by_courier','received_by_customer','completed')
        ) customer_orders ON TRUE
        WHERE ira.influencer_id = ip.id
     ) stats ON TRUE
      LEFT JOIN LATERAL (
        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'campaignId', icc.id,
              'couponId', c.id,
              'code', c.code,
              'label', icc.label,
              'discountType', c.discount_type,
              'discountValue', c.discount_value,
              'minOrderTotal', c.min_order_total,
              'maxUses', c.max_uses,
              'usesCount', c.uses_count,
              'maxUsesPerUser', c.max_uses_per_user,
              'isActive', c.is_active,
              'validFrom', c.valid_from,
              'validUntil', c.valid_until,
              'createdAt', icc.created_at
            ) ORDER BY icc.created_at DESC, icc.id DESC
          ),
          '[]'::jsonb
        ) AS coupons
        FROM influencer_coupon_campaign icc
        JOIN coupon c ON c.id = icc.coupon_id
        WHERE icc.influencer_id = ip.id
      ) coupon_stats ON TRUE
      ORDER BY ip.created_at DESC, ip.id DESC`,
  );
  return result.rows;
}

export async function listInfluencerReferrals(influencerId, { limit = 300 } = {}) {
  const result = await q(
    `SELECT
       ira.id,
       ira.user_id,
       ira.claimed_at,
       u.full_name,
       u.phone,
       ip.qualification_rule,
       completed.first_completed_order_at,
       completed.last_completed_order_at,
       COALESCE(completed.completed_orders, 0)::INT AS completed_orders,
       COALESCE(completed.total_spent, 0)::NUMERIC AS total_spent
     FROM influencer_referral_attribution ira
      JOIN influencer_profile ip ON ip.id = ira.influencer_id
     JOIN app_user u ON u.id = ira.user_id
     LEFT JOIN LATERAL (
       SELECT
         MIN(o.created_at) AS first_completed_order_at,
          MAX(o.created_at) AS last_completed_order_at,
          COUNT(*)::INT AS completed_orders,
          COALESCE(SUM(o.total_amount), 0)::NUMERIC AS total_spent
       FROM customer_order o
       WHERE o.customer_user_id = ira.user_id
         AND o.created_at >= ira.claimed_at
         AND o.status IN ('delivered','delivered_by_courier','received_by_customer','completed')
     ) completed ON TRUE
      WHERE ira.influencer_id = $1
     ORDER BY ira.claimed_at DESC, ira.id DESC
     LIMIT $2`,
    [Number(influencerId), Math.max(1, Math.min(500, Number(limit) || 300))],
  );
  return result.rows;
}

export async function setInfluencerProfileActive(influencerId, isActive) {
  const result = await q(
    `UPDATE influencer_profile
     SET is_active = $2, updated_at = NOW()
     WHERE id = $1
     RETURNING id, is_active`,
    [Number(influencerId), isActive === true],
  );
  return result.rows[0] || null;
}

export async function getCouponById(couponId) {
  const r = await q(`SELECT * FROM coupon WHERE id = $1`, [Number(couponId)]);
  return r.rows[0] || null;
}

export async function isInfluencerCoupon(couponId) {
  const result = await q(
    `SELECT 1
     FROM influencer_coupon_campaign
     WHERE coupon_id = $1
     LIMIT 1`,
    [Number(couponId)],
  );
  return Boolean(result.rows[0]);
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
