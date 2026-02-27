import { Router } from "express";
import * as c from "./admin.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import { requireBackoffice } from "../../shared/middleware/backoffice.middleware.js";
import { requireSuperAdmin } from "../../shared/middleware/super-admin.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const adminRouter = Router();

adminRouter.use(requireAuth, requireBackoffice);

adminRouter.get("/analytics", c.analytics);
adminRouter.get("/customers/insights", requireSuperAdmin, c.customerInsightsList);
adminRouter.get(
  "/customers/:customerUserId/insights",
  requireSuperAdmin,
  c.customerInsightDetails
);
adminRouter.get("/orders/print-report", c.printOrdersReport);
adminRouter.get("/merchants", c.merchants);
adminRouter.get("/merchants/pending", c.pendingMerchants);
adminRouter.get("/delivery/pending", c.pendingDeliveryAccounts);
adminRouter.get("/settlements/pending", c.pendingSettlements);
adminRouter.get("/owners/available", c.availableOwners);

adminRouter.post("/users", requireAdmin, imageUpload.single("imageFile"), c.createUser);
adminRouter.patch("/merchants/:merchantId/approve", requireAdmin, c.approveMerchant);
adminRouter.patch(
  "/delivery/:deliveryUserId/approve",
  requireAdmin,
  c.approveDeliveryAccount
);
adminRouter.patch(
  "/merchants/:merchantId/disabled",
  requireAdmin,
  c.toggleMerchantDisabled
);
adminRouter.patch(
  "/settlements/:settlementId/approve",
  requireAdmin,
  c.approveSettlement
);
