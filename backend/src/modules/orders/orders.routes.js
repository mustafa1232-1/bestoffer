import { Router } from "express";
import * as c from "./orders.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const ordersRouter = Router();

ordersRouter.use(requireAuth, requireCustomer);

ordersRouter.post("/", imageUpload.single("imageFile"), c.create);
ordersRouter.get("/my", c.listMyOrders);
ordersRouter.get("/favorites/ids", c.listFavoriteProductIds);
ordersRouter.get("/favorites", c.listFavoriteProducts);
ordersRouter.post("/favorites/:productId", c.addFavoriteProduct);
ordersRouter.delete("/favorites/:productId", c.removeFavoriteProduct);
ordersRouter.post("/:orderId/reorder", c.reorder);
ordersRouter.post("/:orderId/confirm-delivered", c.confirmDelivered);
ordersRouter.post("/:orderId/rate-delivery", c.rateDelivery);
ordersRouter.post("/:orderId/rate-merchant", c.rateMerchant);
