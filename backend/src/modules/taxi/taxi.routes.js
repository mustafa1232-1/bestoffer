import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requireDelivery } from "../../shared/middleware/delivery.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as deliveryController from "../delivery/delivery.controller.js";
import * as c from "./taxi.controller.js";

export const taxiRouter = Router();

taxiRouter.get("/public/track/:token", c.publicTrack);
taxiRouter.post(
  "/captain/register",
  imageUpload.fields([
    { name: "profileImageFile", maxCount: 1 },
    { name: "carImageFile", maxCount: 1 },
  ]),
  deliveryController.register
);

taxiRouter.use(requireAuth);

taxiRouter.get("/stream", c.stream);

taxiRouter.get("/rides/current", requireCustomer, c.getCurrentRideForCustomer);
taxiRouter.post("/rides", requireCustomer, c.createRide);
taxiRouter.get("/rides/:rideId", c.getRideDetails);
taxiRouter.post("/rides/:rideId/cancel", requireCustomer, c.cancelRide);
taxiRouter.post(
  "/rides/:rideId/bids/:bidId/accept",
  requireCustomer,
  c.acceptBid
);
taxiRouter.post("/rides/:rideId/share-token", requireCustomer, c.createShareToken);

taxiRouter.post("/captain/presence", requireDelivery, c.upsertPresence);
taxiRouter.get(
  "/captain/nearby-requests",
  requireDelivery,
  c.listNearbyRequests
);
taxiRouter.get("/captain/current-ride", requireDelivery, c.getCurrentRideForCaptain);
taxiRouter.get("/captain/history", requireDelivery, c.listCaptainHistory);

taxiRouter.post("/rides/:rideId/bids", requireDelivery, c.createBid);
taxiRouter.post("/rides/:rideId/arrive", requireDelivery, c.markArrived);
taxiRouter.post("/rides/:rideId/start", requireDelivery, c.startRide);
taxiRouter.post("/rides/:rideId/complete", requireDelivery, c.completeRide);
taxiRouter.post("/rides/:rideId/location", requireDelivery, c.updateLocation);
