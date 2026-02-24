import { Router } from "express";
import * as c from "./owner.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireOwner } from "../../shared/middleware/owner.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const ownerRouter = Router();

ownerRouter.post(
  "/register",
  imageUpload.fields([
    { name: "ownerImageFile", maxCount: 1 },
    { name: "merchantImageFile", maxCount: 1 },
  ]),
  c.register
);

ownerRouter.use(requireAuth, requireOwner);

ownerRouter.get("/merchant", c.getMerchant);
ownerRouter.put("/merchant", imageUpload.single("imageFile"), c.updateMerchant);

ownerRouter.get("/categories", c.listCategories);
ownerRouter.post("/categories", c.createCategory);
ownerRouter.put("/categories/:categoryId", c.updateCategory);
ownerRouter.delete("/categories/:categoryId", c.deleteCategory);

ownerRouter.get("/products", c.listProducts);
ownerRouter.post("/products", imageUpload.single("imageFile"), c.createProduct);
ownerRouter.put(
  "/products/:productId",
  imageUpload.single("imageFile"),
  c.updateProduct
);
ownerRouter.delete("/products/:productId", c.deleteProduct);

ownerRouter.get("/delivery-agents", c.listDeliveryAgents);
ownerRouter.get("/orders/current", c.listCurrentOrders);
ownerRouter.get("/orders/history", c.listOrderHistory);
ownerRouter.patch("/orders/:orderId/status", c.updateOrderStatus);
ownerRouter.patch("/orders/:orderId/assign-delivery", c.assignDelivery);
ownerRouter.get("/analytics", c.analytics);
ownerRouter.get("/orders/print-report", c.printOrdersReport);
ownerRouter.get("/settlements/summary", c.settlementSummary);
ownerRouter.post("/settlements/request", c.requestSettlement);
