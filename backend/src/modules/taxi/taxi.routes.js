import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requireTaxiCaptain } from "../../shared/middleware/taxi-captain.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./taxi.controller.js";
import * as loyalty from "./taxi.loyalty.controller.js";

export const taxiRouter = Router();

taxiRouter.get("/public/track/:token", c.publicTrack);
taxiRouter.get("/public/track/:token/stream", c.publicTrackStream);
taxiRouter.get("/vehicle-catalog", c.listVehicleCatalog);
taxiRouter.post("/vehicle-catalog/makes", c.createVehicleMake);
taxiRouter.post("/vehicle-catalog/models", c.createVehicleModel);
taxiRouter.post(
  "/captain/register",
  imageUpload.fields([
    { name: "profileImageFile", maxCount: 1 },
    { name: "carImageFile", maxCount: 1 },
  ]),
  c.registerCaptain
);

taxiRouter.use(requireAuth);

taxiRouter.get("/stream", c.stream);

taxiRouter.get("/rides/current", requireCustomer, c.getCurrentRideForCustomer);
taxiRouter.get("/rides/history/me", requireCustomer, c.listMyRideHistory);
taxiRouter.post("/rides", requireCustomer, c.createRide);
taxiRouter.post("/rides/:rideId/rebook", requireCustomer, c.rebookRide);
taxiRouter.post("/rides/:rideId/raise-fare", requireCustomer, c.raiseRideFare);
taxiRouter.get("/captains/nearby", requireCustomer, c.listNearbyCaptains);
taxiRouter.get("/rides/:rideId", c.getRideDetails);
taxiRouter.post("/rides/:rideId/cancel", requireCustomer, c.cancelRide);
// مخرج الطوارئ متاح للطرفين (زبون/كابتن) — التحقق من كونه طرفاً يتم في الـservice.
taxiRouter.post("/rides/:rideId/emergency", c.raiseRideEmergency);
taxiRouter.post("/rides/:rideId/rate", requireCustomer, c.rateRide);
taxiRouter.post(
  "/rides/:rideId/bids/current/reject",
  requireCustomer,
  c.rejectCurrentBid
);
taxiRouter.post(
  "/rides/:rideId/bids/current/counter",
  requireCustomer,
  c.counterOfferCurrentBid
);
taxiRouter.post(
  "/rides/:rideId/bids/:bidId/accept",
  requireCustomer,
  c.acceptBid
);
taxiRouter.post(
  "/rides/:rideId/bids/:bidId/reject",
  requireCustomer,
  c.rejectBid
);
taxiRouter.post(
  "/rides/:rideId/bids/:bidId/counter",
  requireCustomer,
  c.counterOfferBid
);
taxiRouter.post("/rides/:rideId/share-token", requireCustomer, c.createShareToken);
taxiRouter.get(
  "/rides/:rideId/share/friends",
  requireCustomer,
  c.listRideSharedFriends
);
taxiRouter.post(
  "/rides/:rideId/share/friends",
  requireCustomer,
  c.shareRideWithFriends
);
taxiRouter.get("/rides/:rideId/shared-track", c.getSharedRideTrack);
taxiRouter.get("/rides/:rideId/chat", c.listRideChat);
taxiRouter.post("/rides/:rideId/chat", c.sendRideChat);
taxiRouter.get("/rides/:rideId/call", c.getRideCallState);
taxiRouter.post("/rides/:rideId/call/start", c.startRideCall);
taxiRouter.post("/rides/:rideId/call/signal", c.sendRideCallSignal);
taxiRouter.post("/rides/:rideId/call/end", c.endRideCall);
taxiRouter.get("/saved-places", requireCustomer, loyalty.listSavedPlaces);
taxiRouter.post("/saved-places", requireCustomer, loyalty.createSavedPlace);
taxiRouter.patch(
  "/saved-places/:id",
  requireCustomer,
  loyalty.updateSavedPlace
);
taxiRouter.delete(
  "/saved-places/:id",
  requireCustomer,
  loyalty.deleteSavedPlace
);
taxiRouter.post(
  "/saved-places/import-default-addresses",
  requireCustomer,
  loyalty.importSavedPlaces
);
taxiRouter.get("/favorite-trips", requireCustomer, loyalty.listFavoriteTrips);
taxiRouter.post("/favorite-trips", requireCustomer, loyalty.createFavoriteTrip);
taxiRouter.patch(
  "/favorite-trips/:id",
  requireCustomer,
  loyalty.updateFavoriteTrip
);
taxiRouter.delete(
  "/favorite-trips/:id",
  requireCustomer,
  loyalty.deleteFavoriteTrip
);
taxiRouter.get("/scheduled-rides", requireCustomer, loyalty.listScheduledRides);
taxiRouter.post(
  "/scheduled-rides",
  requireCustomer,
  loyalty.createScheduledRide
);
taxiRouter.post(
  "/scheduled-rides/:id/cancel",
  requireCustomer,
  loyalty.cancelScheduledRide
);
taxiRouter.get("/coupons/mine", requireCustomer, loyalty.listMyCoupons);
taxiRouter.post("/coupons/preview", requireCustomer, loyalty.previewCoupon);
taxiRouter.get(
  "/rides/:rideId/complaint-eligibility",
  requireCustomer,
  loyalty.getRideComplaintEligibility
);
taxiRouter.get("/complaints", requireCustomer, loyalty.listMyComplaints);
taxiRouter.post("/complaints", requireCustomer, loyalty.createComplaint);

taxiRouter.post("/captain/presence", requireTaxiCaptain, c.upsertPresence);
taxiRouter.get(
  "/captain/nearby-requests",
  requireTaxiCaptain,
  c.listNearbyRequests
);
taxiRouter.get(
  "/captain/current-ride",
  requireTaxiCaptain,
  c.getCurrentRideForCaptain
);
taxiRouter.get("/captain/history", requireTaxiCaptain, c.listCaptainHistory);
taxiRouter.get("/captain/dashboard", requireTaxiCaptain, c.getCaptainDashboard);
taxiRouter.get("/captain/profile", requireTaxiCaptain, c.getCaptainProfile);
taxiRouter.get(
  "/captain/subscription",
  requireTaxiCaptain,
  c.getCaptainSubscription
);
taxiRouter.post(
  "/captain/subscription/request-cash-payment",
  requireTaxiCaptain,
  c.requestCaptainCashPayment
);
taxiRouter.post(
  "/captain/profile-edit-requests",
  requireTaxiCaptain,
  c.requestCaptainProfileEdit
);

taxiRouter.post("/rides/:rideId/bids", requireTaxiCaptain, c.createBid);
taxiRouter.post(
  "/rides/:rideId/captain/accept-customer-fare",
  requireTaxiCaptain,
  c.acceptCustomerFare
);
taxiRouter.post("/rides/:rideId/decline", requireTaxiCaptain, c.declineRideByCaptain);
taxiRouter.post("/rides/:rideId/captain/cancel", requireTaxiCaptain, c.cancelRideByCaptain);
taxiRouter.post("/rides/:rideId/arrive", requireTaxiCaptain, c.markArrived);
taxiRouter.post("/rides/:rideId/start", requireTaxiCaptain, c.startRide);
taxiRouter.post("/rides/:rideId/complete", requireTaxiCaptain, c.completeRide);
taxiRouter.post("/rides/:rideId/location", requireTaxiCaptain, c.updateLocation);
taxiRouter.post(
  "/rides/:rideId/rider-rating",
  requireTaxiCaptain,
  loyalty.rateRiderByCaptain
);
taxiRouter.get(
  "/captain/subscription/ledger",
  requireTaxiCaptain,
  loyalty.captainSubscriptionLedger
);
taxiRouter.get("/captain/contests", requireTaxiCaptain, loyalty.captainContests);
taxiRouter.get("/captain/rewards", requireTaxiCaptain, loyalty.captainRewards);
taxiRouter.get(
  "/captain/status",
  requireTaxiCaptain,
  loyalty.captainGovernanceStatus
);
