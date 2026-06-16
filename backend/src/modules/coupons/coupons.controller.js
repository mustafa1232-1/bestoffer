import * as service from "./coupons.service.js";

// ── Customer ──────────────────────────────────────────────────────────────────

/**
 * POST /api/coupons/validate
 * Body: { code, merchantId?, orderTotal?, orderSubtotal? }
 */
export async function validateCoupon(req, res, next) {
  try {
    const { code, merchantId, orderTotal, orderSubtotal } = req.body || {};
    const out = await service.validateCoupon(code, {
      customerId: req.userId,
      merchantId,
      orderTotal,
      orderSubtotal,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

// ── Admin / Owner ─────────────────────────────────────────────────────────────

export async function listMyCoupons(req, res, next) {
  try {
    const { merchantId, limit = 80 } = req.query || {};
    const out = await service.listCustomerCoupons(
      {
        merchantId: merchantId ? Number(merchantId) : undefined,
        limit: Math.min(120, Number(limit) || 80),
      },
      { userId: req.userId }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createCoupon(req, res, next) {
  try {
    const out = await service.createCoupon(req.body || {}, {
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function listCoupons(req, res, next) {
  try {
    const { merchantId, activeOnly, limit = 50, offset = 0 } = req.query || {};
    const out = await service.listCoupons({
      merchantId: merchantId ? Number(merchantId) : undefined,
      activeOnly: activeOnly === "true",
      limit: Math.min(100, Number(limit) || 50),
      offset: Number(offset) || 0,
    }, {
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function toggleCouponActive(req, res, next) {
  try {
    const isActive = req.body?.isActive;
    if (typeof isActive !== "boolean") {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: ["isActive"] });
    }
    const out = await service.toggleCouponActive(req.params.couponId, isActive, {
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function getCouponStats(req, res, next) {
  try {
    const { merchantId, includeGlobal, days } = req.query || {};
    const out = await service.getCouponStats(
      {
        merchantId: merchantId ? Number(merchantId) : undefined,
        includeGlobal: parseBool(includeGlobal, true),
        days: Number(days) || 30,
      },
      {
        userId: req.userId,
        role: req.userRole,
        isSuperAdmin: req.userIsSuperAdmin === true,
      },
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteCoupon(req, res, next) {
  try {
    const out = await service.deleteCoupon(req.params.couponId, {
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

function parseBool(value, fallback) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
    if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  }
  return fallback;
}
