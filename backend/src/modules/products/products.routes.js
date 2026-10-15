import { Router } from "express";
import * as c from "./products.controller.js";
import * as commerceController from "../commerce/commerce.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";

export const productsRouter = Router();

// Compatibility route for clients released before the commerce search route
// was namespaced under /api/commerce. Keep it customer-only like the canonical
// endpoint so the alias cannot become a public catalog data leak.
productsRouter.get(
  "/search",
  requireAuth,
  requireCustomer,
  commerceController.searchProductsGlobal,
);

productsRouter.get("/:productId/summary", c.summary);
productsRouter.get("/:productId/details", c.details);
