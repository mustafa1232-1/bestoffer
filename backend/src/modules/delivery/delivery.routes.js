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

deliveryRouter.use(requireAuth);

// Numeric constraint so this parameterized route does NOT shadow the literal
// "/orders/current" and "/orders/history" routes below (otherwise a request to
// /orders/current matched :orderId="current" -> Number("current")=NaN -> 500).
deliveryRouter.get("/orders/:orderId(\\d+)", c.orderDetail);
deliveryRouter.use(requireDeliveryAgent);
deliveryRouter.get("/orders/current", c.currentOrders);
deliveryRouter.get("/orders/history", c.history);
deliveryRouter.patch("/orders/:orderId/claim", c.claimOrder);
deliveryRouter.patch("/orders/:orderId/start", c.startOrder);
deliveryRouter.patch("/orders/:orderId/arrived", c.markArrived);
deliveryRouter.patch("/orders/:orderId/delivered", c.markDelivered);
deliveryRouter.get("/end-day/readiness", c.endDayReadiness);
deliveryRouter.post("/end-day", c.endDay);
deliveryRouter.get("/analytics", c.analytics);
deliveryRouter.get("/earnings", c.earnings);
deliveryRouter.get("/ratings", c.ratings);

// Grouped multi-store delivery jobs (delivery closure §8). Literal segments
// precede the parameterized :deliveryJobId route so they are not shadowed.
deliveryRouter.get("/delivery-jobs/current", c.currentGroupedJob);
deliveryRouter.get("/delivery-jobs/history", c.groupedJobHistory);
deliveryRouter.get("/delivery-jobs", c.listGroupedJobs);
deliveryRouter.get("/delivery-jobs/:deliveryJobId(\\d+)", c.groupedJobDetails);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/acknowledge", c.acknowledgeGroupedJob);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/heading-to-pickups", c.groupedHeadingToPickups);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/stops/:stopId(\\d+)/arrived", c.groupedStopArrived);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/stops/:stopId(\\d+)/collected", c.groupedStopCollected);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/heading-to-customer", c.groupedHeadingToCustomer);
deliveryRouter.post("/delivery-jobs/:deliveryJobId(\\d+)/delivered", c.groupedDelivered);
