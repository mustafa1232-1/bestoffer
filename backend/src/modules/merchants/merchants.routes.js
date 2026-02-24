import { Router } from "express";
import * as c from "./merchants.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const merchantsRouter = Router();

merchantsRouter.get("/", c.list);
merchantsRouter.get("/:merchantId/products", c.listProducts);
merchantsRouter.get("/:merchantId/categories", c.listCategories);
merchantsRouter.post(
  "/",
  requireAuth,
  requireAdmin,
  imageUpload.fields([
    { name: "merchantImageFile", maxCount: 1 },
    { name: "ownerImageFile", maxCount: 1 },
  ]),
  c.create
);
