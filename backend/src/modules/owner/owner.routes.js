import { Router } from "express";
import * as c from "./owner.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireOwner } from "../../shared/middleware/owner.middleware.js";
import { requireSignedRequest } from "../../shared/middleware/request-signing.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const ownerRouter = Router();
const requireSensitiveWriteSignature = requireSignedRequest();

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
ownerRouter.post("/merchant/financial-terms/accept", c.acceptFinancialTerms);
ownerRouter.post("/merchant/financial-terms/reject", c.rejectFinancialTerms);
ownerRouter.put("/merchant", imageUpload.single("imageFile"), c.updateMerchant);

ownerRouter.get("/categories", c.listCategories);
ownerRouter.post("/categories", c.createCategory);
ownerRouter.put("/categories/:categoryId", c.updateCategory);
ownerRouter.delete("/categories/:categoryId", c.deleteCategory);

ownerRouter.get("/products", c.listProducts);
ownerRouter.get("/offers", c.listOffers);
const productImageFields = imageUpload.fields([
  { name: "imageFile", maxCount: 1 },
  { name: "galleryFiles", maxCount: 30 },
  { name: "variantFiles", maxCount: 100 },
]);
ownerRouter.post("/products", productImageFields, c.createProduct);
ownerRouter.post("/offers", c.createOffer);
ownerRouter.put(
  "/products/:productId",
  productImageFields,
  c.updateProduct
);
ownerRouter.patch("/products/:productId/availability", c.updateProductAvailability);
ownerRouter.patch("/offers/:offerId", c.updateOffer);
ownerRouter.delete("/products/:productId", c.deleteProduct);
ownerRouter.delete("/offers/:offerId", c.deleteOffer);

ownerRouter.get("/delivery-agents", c.listDeliveryAgents);
ownerRouter.post(
  "/delivery-agents",
  imageUpload.single("imageFile"),
  c.createDeliveryAgent
);
ownerRouter.post("/staff/delivery/assign-existing", c.assignExistingDeliveryAgent);
ownerRouter.get("/staff/users/search", c.searchStaffUsers);
ownerRouter.get("/accountants", c.listAccountants);
ownerRouter.post("/accountants", imageUpload.single("imageFile"), c.createAccountant);
ownerRouter.post("/staff/accountants/assign-existing", c.assignExistingAccountant);
ownerRouter.get("/hr-staff", c.listHrStaff);
ownerRouter.post("/hr-staff", imageUpload.single("imageFile"), c.createHrStaff);
ownerRouter.post("/staff/hr/assign-existing", c.assignExistingHrStaff);
ownerRouter.get("/orders/current", c.listCurrentOrders);
ownerRouter.get("/orders/history", c.listOrderHistory);
ownerRouter.patch("/orders/:orderId/status", c.updateOrderStatus);
ownerRouter.patch("/orders/:orderId/assign-delivery", c.assignDelivery);
ownerRouter.patch("/orders/:orderId/items/:productId/unavailable", c.markOrderItemUnavailable);
ownerRouter.get("/analytics", c.analytics);
ownerRouter.get("/orders/print-report", c.printOrdersReport);
ownerRouter.get("/settlements/summary", c.settlementSummary);
ownerRouter.post(
  "/settlements/request",
  requireSensitiveWriteSignature,
  c.requestSettlement
);
