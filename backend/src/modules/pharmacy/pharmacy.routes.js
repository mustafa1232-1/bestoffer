import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requireOwner } from "../../shared/middleware/owner.middleware.js";
import { chatAttachmentUpload } from "../../shared/utils/upload.js";
import * as c from "./pharmacy.controller.js";

export const pharmacyRouter = Router();

pharmacyRouter.get("/attachments/:id/content", c.attachmentContent);

pharmacyRouter.use(requireAuth);

pharmacyRouter.post("/conversations", requireCustomer, c.createConversation);
pharmacyRouter.get("/conversations", c.listConversations);
pharmacyRouter.get("/conversations/:id", c.getConversationDetails);
pharmacyRouter.post("/conversations/:id/messages", c.sendMessage);
pharmacyRouter.post(
  "/conversations/:id/attachments",
  chatAttachmentUpload.single("file"),
  c.uploadAttachment
);
pharmacyRouter.post(
  "/conversations/:id/proposed-carts",
  requireOwner,
  c.createProposedCart
);
pharmacyRouter.post("/proposed-carts/:id/accept", requireCustomer, c.acceptProposedCart);
pharmacyRouter.post("/proposed-carts/:id/reject", requireCustomer, c.rejectProposedCart);
pharmacyRouter.post(
  "/proposed-carts/:id/request-revision",
  requireCustomer,
  c.requestCartRevision
);
pharmacyRouter.post("/proposed-carts/:id/convert-to-order", c.convertProposedCartToOrder);
pharmacyRouter.get("/attachments/:id/access-url", c.attachmentAccessUrl);
