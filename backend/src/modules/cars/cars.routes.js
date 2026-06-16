import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./cars.controller.js";

export const carsRouter = Router();

carsRouter.get("/brands", c.listBrands);
carsRouter.get("/models", c.listModels);
carsRouter.get("/browse", c.browse);
carsRouter.get("/listings", c.listListings);
carsRouter.get("/listings/:listingId", c.getListing);
carsRouter.use(requireAuth, requireCustomer);
carsRouter.post("/smart-search", c.smartSearch);
carsRouter.get("/entitlements", c.entitlements);
carsRouter.get("/workspace", c.getWorkspace);
carsRouter.post("/listings", imageUpload.array("imageFiles", 6), c.createListing);
carsRouter.patch("/listings/:listingId", imageUpload.array("imageFiles", 6), c.updateListing);
carsRouter.post("/listings/:listingId/mark-status", c.markStatus);
