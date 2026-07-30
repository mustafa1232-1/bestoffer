import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requirePermission } from "../../shared/middleware/permission.middleware.js";
import * as c from "./coupons.controller.js";

export const couponsRouter = Router();

// Customer: validate a coupon before checkout
couponsRouter.post("/validate", requireAuth, c.validateCoupon);
couponsRouter.get("/mine", requireAuth, requireCustomer, c.listMyCoupons);

// Management: super-admin and owner (owner is scoped to his merchant only)
couponsRouter.get("/stats", requireAuth, c.getCouponStats);
// Employee referral / sales-attribution coupons — gated by an explicit RBAC
// permission (super-admin bypasses). Previously these were open to any
// authenticated caller; now only holders of coupons.agents.manage may reach the
// employee-coupon monitoring, redemptions, and discount controls.
couponsRouter.get(
  "/agents",
  requireAuth,
  requirePermission("coupons.agents.manage"),
  c.listAgentReferralCoupons
);
couponsRouter.get(
  "/:couponId/redemptions",
  requireAuth,
  requirePermission("coupons.agents.manage"),
  c.getAgentCouponRedemptions
);
couponsRouter.get("/", requireAuth, c.listCoupons);
couponsRouter.post("/", requireAuth, c.createCoupon);
couponsRouter.patch("/:couponId/active", requireAuth, c.toggleCouponActive);
couponsRouter.patch(
  "/:couponId/discount",
  requireAuth,
  requirePermission("coupons.agents.manage"),
  c.updateCoupon
);
couponsRouter.delete("/:couponId", requireAuth, c.deleteCoupon);
