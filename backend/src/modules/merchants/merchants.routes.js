import { Router } from "express";
import * as c from "./merchants.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";

export const merchantsRouter = Router();
export const merchantsPublicRouter = Router();

merchantsPublicRouter.get("/", c.list);
merchantsPublicRouter.get("/activities", c.listActivities);
merchantsPublicRouter.get("/discovery/options", c.listActivityDiscoveryOptions);
merchantsPublicRouter.get("/:merchantId(\\d+)", c.getById);
merchantsPublicRouter.get("/:merchantId(\\d+)/products", c.listProducts);
merchantsPublicRouter.get("/:merchantId(\\d+)/categories", c.listCategories);

merchantsRouter.get("/discovery", requireAuth, requireCustomer, c.discovery);
merchantsRouter.get("/ad-board", requireAuth, requireCustomer, c.adBoard);
merchantsRouter.get("/nearby", requireAuth, requireCustomer, c.nearby);
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
