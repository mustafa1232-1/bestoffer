import { Router } from "express";
import * as c from "./orders.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const ordersRouter = Router();

ordersRouter.get("/public/track/:token", c.publicTrack);
ordersRouter.get("/public/track/:token/stream", c.publicTrackStream);

ordersRouter.use(requireAuth);

ordersRouter.post(
  "/preview",
  requireCustomer,
  imageUpload.single("imageFile"),
  c.preview
);
ordersRouter.post("/", requireCustomer, imageUpload.single("imageFile"), c.create);
ordersRouter.get("/my", requireCustomer, c.listMyOrders);
ordersRouter.get("/action-reasons", c.listActionReasons);
ordersRouter.get("/groups/:groupId", requireCustomer, c.getOrderGroupDetails);
ordersRouter.get("/favorites/ids", requireCustomer, c.listFavoriteProductIds);
ordersRouter.get("/favorites", requireCustomer, c.listFavoriteProducts);
ordersRouter.post("/favorites/:productId", requireCustomer, c.addFavoriteProduct);
ordersRouter.delete(
  "/favorites/:productId",
  requireCustomer,
  c.removeFavoriteProduct
);
ordersRouter.post("/:orderId/cancel", requireCustomer, c.cancelByCustomer);
ordersRouter.post(
  "/:orderId/request-return",
  requireCustomer,
  c.requestReturnByCustomer
);
ordersRouter.post("/:orderId/reorder", requireCustomer, c.reorder);
// Tracking is role-aware: the customer owner, the assigned courier, the
// merchant owner and admins can all view it. Authorization is resolved
// per-order inside the service (see getOrderTrackingSnapshotForViewer), so
// this route only needs the shared requireAuth applied above — not the
// customer-only gate, which previously 403'd assigned couriers.
ordersRouter.get("/:orderId/tracking", c.getTrackingSnapshot);
ordersRouter.post("/:orderId/share-token", requireCustomer, c.createShareToken);
ordersRouter.post(
  "/:orderId/confirm-delivered",
  requireCustomer,
  c.confirmDelivered
);
ordersRouter.post("/:orderId/rate-delivery", requireCustomer, c.rateDelivery);
ordersRouter.post("/:orderId/rate-merchant", requireCustomer, c.rateMerchant);

ordersRouter.get(
  "/products/:productId/reviews",
  requireCustomer,
  c.listProductReviews
);
ordersRouter.post(
  "/products/:productId/reviews",
  requireCustomer,
  c.submitProductReview
);
ordersRouter.delete(
  "/products/:productId/reviews",
  requireCustomer,
  c.deleteProductReview
);
