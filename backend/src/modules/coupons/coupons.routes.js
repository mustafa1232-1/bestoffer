import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import * as c from "./coupons.controller.js";

export const couponsRouter = Router();

// Customer: validate a coupon before checkout
couponsRouter.post("/validate", requireAuth, c.validateCoupon);
couponsRouter.get("/mine", requireAuth, requireCustomer, c.listMyCoupons);

// Management: super-admin and owner (owner is scoped to his merchant only)
couponsRouter.get("/stats", requireAuth, c.getCouponStats);
// Employee referral coupons — super-admin sales attribution report
couponsRouter.get("/agents", requireAuth, c.listAgentReferralCoupons);
couponsRouter.get(
  "/:couponId/redemptions",
  requireAuth,
  c.getAgentCouponRedemptions
);
couponsRouter.get("/", requireAuth, c.listCoupons);
couponsRouter.post("/", requireAuth, c.createCoupon);
couponsRouter.patch("/:couponId/active", requireAuth, c.toggleCouponActive);
couponsRouter.patch("/:couponId/discount", requireAuth, c.updateCoupon);
couponsRouter.delete("/:couponId", requireAuth, c.deleteCoupon);
