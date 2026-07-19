import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./coupons.repo.js";

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
