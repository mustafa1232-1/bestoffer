import { Router } from "express";
import * as c from "./delivery.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdminOrOwner } from "../../shared/middleware/backoffice.middleware.js";
import { requireDelivery } from "../../shared/middleware/delivery.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const deliveryRouter = Router();

deliveryRouter.post(
  "/register",
  requireAuth,
  requireAdminOrOwner,
  imageUpload.single("imageFile"),
  c.register
);

deliveryRouter.use(requireAuth, requireDelivery);

deliveryRouter.get("/orders/current", c.currentOrders);
deliveryRouter.get("/orders/history", c.history);
deliveryRouter.patch("/orders/:orderId/claim", c.claimOrder);
deliveryRouter.patch("/orders/:orderId/start", c.startOrder);
deliveryRouter.patch("/orders/:orderId/delivered", c.markDelivered);
deliveryRouter.post("/end-day", c.endDay);
deliveryRouter.get("/analytics", c.analytics);
