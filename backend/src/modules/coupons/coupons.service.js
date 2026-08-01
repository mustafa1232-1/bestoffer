import { AppError } from "../../shared/utils/errors.js";
import { checkPermission } from "../security/permissions.service.js";
import { computeOrderFinancialSnapshot } from "../commerce/merchant-financial.logic.js";
import * as repo from "./coupons.repo.js";

const DEFAULT_AGENT_COMMISSION_SHARE_PERCENT = 25;

function normalizeSharePercent(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return DEFAULT_AGENT_COMMISSION_SHARE_PERCENT;
  return Math.max(0, Math.min(100, n));
}

/**
 * Validate a coupon code and return the potential discount.
 * Called by the customer before placing an order.
 */
export async function validateCoupon(
  code,
  { customerId, merchantId, orderTotal, orderSubtotal }
) {
  if (!code || typeof code !== "string" || !code.trim()) {
    const err = new Error("COUPON_CODE_REQUIRED");
    err.status = 400;
    throw err;
  }

  const eligibleAmount = Number(
    orderSubtotal == null || orderSubtotal === ""
      ? orderTotal || 0
      : orderSubtotal
  );

  const normalizedCustomerId = Number(customerId);
  const normalizedMerchantId = Number(merchantId);
  const result = await repo.validateCouponByCode(code.trim(), {
    customerId: Number.isFinite(normalizedCustomerId) && normalizedCustomerId > 0
      ? normalizedCustomerId
      : null,
    merchantId:
      Number.isFinite(normalizedMerchantId) && normalizedMerchantId > 0
        ? normalizedMerchantId
        : null,
    orderTotal: eligibleAmount,
  });

  if (!result?.coupon) {
    const err = new Error(result?.reasonCode || "COUPON_INVALID_OR_EXPIRED");
    err.status = 404;
    throw err;
  }
  const coupon = result.coupon;

  const discountAmount = repo.calcDiscount(coupon, eligibleAmount);

  return {
    coupon: {
      id: coupon.id,
      code: coupon.code,
      discountType: coupon.discount_type,
      discountValue: Number(coupon.discount_value),
      description: coupon.description,
    },
    eligibleAmount,
    discountAmount,
    finalTotal: Math.max(0, eligibleAmount - discountAmount),
  };
}

// ── Admin management ──────────────────────────────────────────────────────────

export async function listCustomerCoupons(query = {}, actor = {}) {
  const customerId = Number(actor?.userId || 0);
  if (!Number.isFinite(customerId) || customerId <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }

  const merchantIdRaw = Number(query?.merchantId || 0);
  const merchantId =
    Number.isFinite(merchantIdRaw) && merchantIdRaw > 0
      ? merchantIdRaw
      : null;
  const limit = Math.max(1, Math.min(120, Number(query?.limit) || 80));

  const rows = await repo.listCustomerCoupons({
    customerId,
    merchantId,
    limit,
  });

  return {
    coupons: rows.map((row) => ({
      id: Number(row.id),
      code: row.code,
      description: row.description || null,
      discountType: row.discount_type,
      discountValue: Number(row.discount_value || 0),
      minOrderTotal: Number(row.min_order_total || 0),
      maxUses: row.max_uses == null ? null : Number(row.max_uses),
      usesCount: Number(row.uses_count || 0),
      remainingUsesTotal:
        row.remaining_uses_total == null
          ? null
          : Number(row.remaining_uses_total),
      validFrom: row.valid_from || null,
      validUntil: row.valid_until || null,
      scopeKind: row.scope_kind || "global",
      merchantId: row.merchant_id == null ? null : Number(row.merchant_id),
      merchantName: row.merchant_name || null,
      companyId: row.company_id == null ? null : Number(row.company_id),
      companyName: row.company_name || null,
      companyAppliesToAllBranches: row.company_applies_to_all_branches === true,
      targetMerchants: Array.isArray(row.target_merchants)
        ? row.target_merchants
        : [],
      status: row.coupon_status || "unknown",
      couponStatus: row.coupon_status || "unknown",
      isEffectivelyActive: row.coupon_status === "active",
      createdAt: row.created_at || null,
    })),
  };
}

async function resolveCouponManager(actor) {
  const userId = Number(actor?.userId || 0);
  const role = String(actor?.role || "").trim().toLowerCase();
  const isSuperAdmin = actor?.isSuperAdmin === true;

  if (!Number.isFinite(userId) || userId <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }

  if (role === "owner") {
    const merchant = await repo.findOwnerMerchantByUserId(userId);
    if (!merchant?.id) {
      throw new AppError("OWNER_MERCHANT_NOT_FOUND", { status: 404 });
    }
    return { kind: "owner", userId, merchantId: Number(merchant.id) };
  }

  if (role === "admin") {
    if (!isSuperAdmin) {
      throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
    }
    return { kind: "super_admin", userId, merchantId: null };
  }

  throw new AppError("FORBIDDEN_COUPON_MANAGEMENT", { status: 403 });
}

/**
 * Authorization for the employee/agent-coupon monitoring surface
 * (list, redemptions, discount edit). Unlike general coupon CRUD — which is
 * limited to owners and super-admins — these company-wide reports are open to
 * anyone holding the `coupons.agents.manage` permission (staff employees and
 * delegated admins), as well as super-admins. The matching routes already gate
 * on this permission; this resolver enforces it again at the service layer so
 * the scope can never be reached without it.
 */
async function resolveAgentCouponManager(actor) {
  const userId = Number(actor?.userId || 0);
  if (!Number.isFinite(userId) || userId <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }
  const check = await checkPermission(userId, "coupons.agents.manage");
  if (!check.allowed) {
    throw new AppError("FORBIDDEN_COUPON_MANAGEMENT", { status: 403 });
  }
  return { kind: "agent_manager", userId, merchantId: null };
}

function throwCouponValidation(fields, formCode = null) {
  throw new AppError("VALIDATION_ERROR", {
    status: 400,
    details: {
      fields,
      ...(formCode == null ? null : { form: formCode }),
    },
  });
}

export async function createCoupon(dto, actor) {
  const { code, description, discountType, discountValue, minOrderTotal,
          maxUses, merchantId, validFrom, validUntil } = dto;
  const manager = await resolveCouponManager(actor);

  if (!code?.trim()) {
    throwCouponValidation({ code: "REQUIRED" });
  }
  if (!["percent", "fixed"].includes(discountType)) {
    throwCouponValidation({ discountType: "SELECT_OPTION" });
  }
  if (!discountValue || Number(discountValue) <= 0) {
    throwCouponValidation({ discountValue: "INVALID_NUMBER" });
  }
  if (discountType === "percent" && Number(discountValue) > 100) {
    throwCouponValidation({ discountValue: "PERCENT_DISCOUNT_TOO_HIGH" });
  }
  if (Number(minOrderTotal || 0) < 0) {
    throwCouponValidation({ minOrderTotal: "INVALID_NUMBER" });
  }
  if (maxUses != null && maxUses !== "" && Number(maxUses) <= 0) {
    throwCouponValidation({ maxUses: "INVALID_NUMBER" });
  }
  if (validFrom && validUntil) {
    const validFromDate = new Date(validFrom);
    const validUntilDate = new Date(validUntil);
    if (
      Number.isFinite(validFromDate.getTime()) &&
      Number.isFinite(validUntilDate.getTime()) &&
      validUntilDate.getTime() < validFromDate.getTime()
    ) {
      throwCouponValidation({ validUntil: "INVALID_DATE_RANGE" });
    }
  }

  if (manager.kind === "super_admin" && Number(merchantId || 0) > 0) {
    throwCouponValidation(
      { _form: "SUPER_ADMIN_COUPON_MUST_BE_GLOBAL" },
      "SUPER_ADMIN_COUPON_MUST_BE_GLOBAL"
    );
  }

  const scopedMerchantId = manager.kind === "owner" ? manager.merchantId : null;

  const coupon = await repo.createCoupon({
    code, description, discountType, discountValue, minOrderTotal,
    maxUses, merchantId: scopedMerchantId, validFrom, validUntil, createdBy: manager.userId,
  });
  return { coupon };
}

export async function listCoupons(query = {}, actor) {
  const manager = await resolveCouponManager(actor);
  const merchantId = query?.merchantId ? Number(query.merchantId) : null;
  const activeOnly = query?.activeOnly === true;
  const limit = Math.max(1, Math.min(100, Number(query?.limit) || 50));
  const offset = Math.max(0, Number(query?.offset) || 0);

  if (manager.kind === "owner") {
    const coupons = await repo.listCoupons({
      merchantId: manager.merchantId,
      includeGlobal: false,
      activeOnly,
      limit,
      offset,
    });
    return {
      coupons: coupons.map((row) => ({
        ...row,
        status: row.coupon_status || "unknown",
        couponStatus: row.coupon_status || "unknown",
        isEffectivelyActive: row.coupon_status === "active",
      })),
    };
  }

  const coupons = await repo.listCoupons({
    merchantId: merchantId || undefined,
    includeGlobal: true,
    activeOnly,
    limit,
    offset,
  });
  return {
    coupons: coupons.map((row) => ({
      ...row,
      status: row.coupon_status || "unknown",
      couponStatus: row.coupon_status || "unknown",
      isEffectivelyActive: row.coupon_status === "active",
    })),
  };
}

export async function getCouponStats(query = {}, actor) {
  const manager = await resolveCouponManager(actor);
  const days = Math.max(7, Math.min(365, Number(query?.days) || 30));

  if (manager.kind === "owner") {
    const stats = await repo.getCouponStats({
      merchantId: manager.merchantId,
      includeGlobal: false,
      days,
    });
    return {
      scope: { kind: "owner", merchantId: manager.merchantId },
      ...stats,
    };
  }

  const rawMerchantId = Number(query?.merchantId || 0);
  const merchantId = Number.isFinite(rawMerchantId) && rawMerchantId > 0
    ? rawMerchantId
    : null;
  const includeGlobal = merchantId == null ? true : query?.includeGlobal !== false;

  const stats = await repo.getCouponStats({
    merchantId: merchantId || undefined,
    includeGlobal,
    days,
  });

  return {
    scope: {
      kind: "super_admin",
      merchantId,
      includeGlobal,
    },
    ...stats,
  };
}

export async function toggleCouponActive(couponId, isActive, actor) {
  const manager = await resolveCouponManager(actor);
  const id = Number(couponId);
  if (!Number.isFinite(id) || id <= 0) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }

  let updated = false;
  if (manager.kind === "owner") {
    updated = await repo.toggleCouponActiveForOwner({
      couponId: id,
      isActive,
      ownerUserId: manager.userId,
    });
  } else {
    updated = await repo.toggleCouponActive(id, isActive);
  }

  if (!updated) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }
  return { ok: true };
}

// ── Employee referral / sales-attribution coupons ────────────────────────────

/**
 * Creates a GLOBAL, zero-discount referral coupon linked to an employee. Called
 * internally when an admin creates an employee (with the referral option). The
 * coupon works immediately for attribution; the admin can add a discount later
 * via updateCoupon.
 */
export async function createAgentReferralCoupon({
  employeeUserId,
  employeeName,
  adminUserId,
  discountType = "percent",
  discountValue = 0,
  agentCommissionSharePercent = DEFAULT_AGENT_COMMISSION_SHARE_PERCENT,
}) {
  const agentId = Number(employeeUserId);
  if (!Number.isFinite(agentId) || agentId <= 0) {
    throw new AppError("VALIDATION_ERROR", { status: 400 });
  }
  const resolvedType = discountType === "fixed" ? "fixed" : "percent";
  let resolvedValue = Number(discountValue);
  if (!Number.isFinite(resolvedValue) || resolvedValue < 0) resolvedValue = 0;
  if (resolvedType === "percent" && resolvedValue > 100) resolvedValue = 100;
  const code = `REF${agentId}`;
  const coupon = await repo.createCoupon({
    code,
    description: `كوبون إحالة${employeeName ? ` - ${employeeName}` : ""}`,
    discountType: resolvedType,
    discountValue: resolvedValue, // 0 = attribution-only (no customer discount)
    minOrderTotal: 0,
    maxUses: null,
    merchantId: null, // global
    validFrom: null,
    validUntil: null,
    createdBy: Number(adminUserId) || null,
    agentUserId: agentId,
    agentCommissionSharePercent: normalizeSharePercent(
      agentCommissionSharePercent
    ),
  });
  return coupon;
}

/**
 * Reduces the redeemed-order rows (from repo.listAgentCouponEarningRows) into a
 * per-coupon tally of the company commission earned and the employee's share of
 * it, plus a flat, most-recent-first breakdown of each qualifying order.
 */
function aggregateAgentEarnings(rows) {
  const byCoupon = new Map();
  const breakdown = [];
  for (const row of rows || []) {
    const order = row.order_json || {};
    const profile = row.profile_json || {};
    const snapshot = computeOrderFinancialSnapshot(order, profile);
    const companyCommission = Math.max(
      0,
      Math.round(Number(snapshot.commissionAmount) || 0)
    );
    const share = normalizeSharePercent(row.share_percent);
    const earning = Math.round((companyCommission * share) / 100);

    const couponId = Number(row.coupon_id);
    const acc =
      byCoupon.get(couponId) ||
      { redemptions: 0, companyCommission: 0, earnings: 0 };
    acc.redemptions += 1;
    acc.companyCommission += companyCommission;
    acc.earnings += earning;
    byCoupon.set(couponId, acc);

    breakdown.push({
      couponId,
      orderId: row.order_id == null ? null : Number(row.order_id),
      redeemedAt: row.redeemed_at || null,
      orderSubtotal: Math.round(Number(snapshot.subtotal) || 0),
      companyCommission,
      sharePercent: share,
      earning,
    });
  }
  return { byCoupon, breakdown };
}

/**
 * The signed-in employee's own coupon earnings ("كوبوني"): their referral
 * coupon(s), how many completed orders came through each, the company commission
 * those orders generated, and the employee's share of it.
 */
export async function getMyCouponEarnings(agentUserId) {
  const userId = Number(agentUserId);
  if (!Number.isFinite(userId) || userId <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }
  const [coupons, rows] = await Promise.all([
    repo.listAgentCouponsForUser(userId),
    repo.listAgentCouponEarningRows({ agentUserId: userId }),
  ]);
  const { byCoupon, breakdown } = aggregateAgentEarnings(rows);

  const couponViews = coupons.map((c) => {
    const tally = byCoupon.get(Number(c.id)) || {
      redemptions: 0,
      companyCommission: 0,
      earnings: 0,
    };
    return {
      couponId: Number(c.id),
      code: c.code,
      discountType: c.discount_type,
      discountValue: Number(c.discount_value || 0),
      sharePercent: normalizeSharePercent(c.share_percent),
      isActive: c.is_active === true,
      redemptions: tally.redemptions,
      companyCommission: tally.companyCommission,
      earnings: tally.earnings,
    };
  });

  const summary = couponViews.reduce(
    (acc, c) => {
      acc.totalRedemptions += c.redemptions;
      acc.totalCompanyCommission += c.companyCommission;
      acc.totalEarnings += c.earnings;
      return acc;
    },
    { totalRedemptions: 0, totalCompanyCommission: 0, totalEarnings: 0 }
  );

  return {
    hasCoupon: couponViews.length > 0,
    sharePercent: couponViews[0]?.sharePercent ??
      DEFAULT_AGENT_COMMISSION_SHARE_PERCENT,
    coupons: couponViews,
    summary,
    breakdown: breakdown.slice(0, 50),
  };
}

/**
 * Admin (super-admin) updates the discount on a coupon — e.g. attach 5% / 10% /
 * a fixed amount to an employee referral coupon, or set it back to 0 (tracking).
 */
export async function updateCoupon(couponId, { discountType, discountValue }, actor) {
  await resolveAgentCouponManager(actor);
  const id = Number(couponId);
  if (!Number.isFinite(id) || id <= 0) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }
  if (!["percent", "fixed"].includes(discountType)) {
    throwCouponValidation({ discountType: "SELECT_OPTION" });
  }
  const value = Number(discountValue);
  if (!Number.isFinite(value) || value < 0) {
    throwCouponValidation({ discountValue: "INVALID_NUMBER" });
  }
  if (discountType === "percent" && value > 100) {
    throwCouponValidation({ discountValue: "PERCENT_DISCOUNT_TOO_HIGH" });
  }
  const updated = await repo.updateCouponDiscount(id, {
    discountType,
    discountValue: value,
  });
  if (!updated) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }
  return { coupon: updated };
}

/**
 * Admin (super-admin) report: coupons grouped by employee (agent) with
 * attribution stats — customers/orders that came through each employee.
 */
export async function listAgentReferralCoupons(actor) {
  await resolveAgentCouponManager(actor);
  const [rows, earningRows] = await Promise.all([
    repo.listAgentReferralCoupons(),
    repo.listAgentCouponEarningRows({}),
  ]);
  const { byCoupon } = aggregateAgentEarnings(earningRows);
  return {
    agents: rows.map((row) => {
      const tally = byCoupon.get(Number(row.id)) || {
        companyCommission: 0,
        earnings: 0,
      };
      return {
        couponId: Number(row.id),
        code: row.code,
        discountType: row.discount_type,
        discountValue: Number(row.discount_value || 0),
        sharePercent: normalizeSharePercent(row.agent_commission_share_percent),
        isActive: row.is_active === true,
        createdAt: row.created_at || null,
        agentUserId: Number(row.agent_user_id),
        agentName: row.agent_name || null,
        agentPhone: row.agent_phone || null,
        agentRole: row.agent_role || null,
        redemptions: Number(row.redemptions || 0),
        uniqueCustomers: Number(row.unique_customers || 0),
        totalDiscount: Number(row.total_discount || 0),
        companyCommission: tally.companyCommission,
        earnings: tally.earnings,
      };
    }),
  };
}

/**
 * Attribution detail for one agent coupon: the customers/orders that used it.
 */
export async function getAgentCouponRedemptions(couponId, actor) {
  await resolveAgentCouponManager(actor);
  const id = Number(couponId);
  if (!Number.isFinite(id) || id <= 0) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }
  const rows = await repo.listAgentCouponRedemptions(id, { limit: 300 });
  return {
    redemptions: rows.map((row) => ({
      customerId: row.customer_id == null ? null : Number(row.customer_id),
      customerName: row.customer_name || null,
      customerPhone: row.customer_phone || null,
      orderId: row.order_id == null ? null : Number(row.order_id),
      discountAmount: Number(row.discount_amount || 0),
      createdAt: row.created_at || null,
    })),
  };
}

export async function deleteCoupon(couponId, actor) {
  const manager = await resolveCouponManager(actor);
  const id = Number(couponId);
  if (!Number.isFinite(id) || id <= 0) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }

  let deleted = false;
  if (manager.kind === "owner") {
    deleted = await repo.deleteCouponForOwner({
      couponId: id,
      ownerUserId: manager.userId,
    });
  } else {
    deleted = await repo.deleteCoupon(id);
  }

  if (!deleted) {
    throw new AppError("COUPON_NOT_FOUND", { status: 404 });
  }
  return { ok: true };
}
