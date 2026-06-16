import { Router } from "express";
import * as c from "./delivery.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireDeliveryAgent } from "../../shared/middleware/delivery-agent.middleware.js";

/**
 * Purpose:
 * مسارات تطبيق الدلفري للمندوبين المعتمدين: الطلبات الحالية، السجل،
 * transitions التنفيذية، إنهاء اليوم، والتحليلات.
 *
 * Critical notes:
 * - تعتمد هذه المسارات على `requireDeliveryAgent` إضافة إلى auth.
 * - أي failure هنا ينعكس مباشرة على lifecycle الطلب:
 *   ready_for_delivery -> on_the_way -> arrived -> delivered.
 */
export const deliveryRouter = Router();

deliveryRouter.use(requireAuth, requireDeliveryAgent);

deliveryRouter.get("/orders/current", c.currentOrders);
deliveryRouter.get("/orders/history", c.history);
deliveryRouter.patch("/orders/:orderId/claim", c.claimOrder);
deliveryRouter.patch("/orders/:orderId/start", c.startOrder);
deliveryRouter.patch("/orders/:orderId/arrived", c.markArrived);
deliveryRouter.patch("/orders/:orderId/delivered", c.markDelivered);
deliveryRouter.post("/end-day", c.endDay);
deliveryRouter.get("/analytics", c.analytics);
