import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAccountant } from "../../shared/middleware/accountant.middleware.js";
import { requireSignedRequest } from "../../shared/middleware/request-signing.middleware.js";
import * as c from "./accountant.controller.js";

export const accountantRouter = Router();
const requireSensitiveWriteSignature = requireSignedRequest();

accountantRouter.use(requireAuth, requireAccountant);

accountantRouter.get("/summary", c.getSummary);
accountantRouter.get("/pending-delivery-settlements", c.listPendingSettlements);
accountantRouter.post(
  "/pending-delivery-settlements/:settlementId/confirm",
  requireSensitiveWriteSignature,
  c.confirmPendingSettlement
);
accountantRouter.post(
  "/opening-balance",
  requireSensitiveWriteSignature,
  c.addOpeningBalance
);
accountantRouter.post("/expenses", requireSensitiveWriteSignature, c.addExpense);
accountantRouter.get("/ledger", c.listLedger);
accountantRouter.get("/payroll/pending-batches", c.listPendingPayrollBatches);
accountantRouter.get("/payroll/batches/:batchId", c.getPayrollBatch);
accountantRouter.post(
  "/payroll/batches/:batchId/acknowledge",
  requireSensitiveWriteSignature,
  c.acknowledgePayrollBatch
);
accountantRouter.post(
  "/payroll/items/:itemId/pay",
  requireSensitiveWriteSignature,
  c.markPayrollItemPaid
);
