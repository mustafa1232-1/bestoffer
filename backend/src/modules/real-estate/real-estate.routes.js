import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireBackoffice } from "../../shared/middleware/backoffice.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./real-estate.controller.js";

export const realEstateRouter = Router();
export const realEstateAdminRouter = Router();

realEstateRouter.get("/listings", c.listListings);
realEstateRouter.get("/listings/:listingId", c.getListing);
realEstateRouter.get("/listings/:listingId/similar", c.listSimilarListings);
realEstateRouter.use(requireAuth);
realEstateRouter.get("/saved", c.listSavedListings);
realEstateRouter.post("/listings/:listingId/save", c.saveListing);
realEstateRouter.delete("/listings/:listingId/save", c.unsaveListing);
realEstateRouter.get("/workspace", c.getWorkspace);
realEstateRouter.post(
  "/listings",
  imageUpload.array("imageFiles", 10),
  c.createListing
);
realEstateRouter.patch(
  "/listings/:listingId",
  imageUpload.array("imageFiles", 10),
  c.updateListing
);
realEstateRouter.post("/listings/:listingId/mark-status", c.markStatus);

realEstateAdminRouter.use(requireAuth, requireBackoffice);
realEstateAdminRouter.get("/listings/pending", c.listPendingListings);
realEstateAdminRouter.patch("/listings/:listingId/approve", c.approveListing);
realEstateAdminRouter.patch("/listings/:listingId/reject", c.rejectListing);
