import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import * as c from "./subscriptions.controller.js";

/**
 * Admin/backoffice surface for the merchant monthly subscription debt
 * lifecycle. Only admin/super-admin can generate invoices, record payments, or
 * waive. Store-side (owner) read access lives in the owner module.
 */
export const subscriptionsAdminRouter = Router();

subscriptionsAdminRouter.use(requireAuth, requireAdmin);

subscriptionsAdminRouter.get("/invoices", c.listInvoices);
subscriptionsAdminRouter.get("/invoices/:invoiceId", c.invoiceDetail);
subscriptionsAdminRouter.post("/generate", c.generate);
subscriptionsAdminRouter.post("/invoices/:invoiceId/payments", c.recordPayment);
subscriptionsAdminRouter.post("/invoices/:invoiceId/waive", c.waiveInvoice);
