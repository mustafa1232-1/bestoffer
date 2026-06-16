import * as loyaltyService from "./taxi.loyalty.service.js";
import {
  validateCaptainRiderRating,
  validateComplaintCreate,
  validateCouponPreview,
  validateEntityId,
  validateFavoriteTripCreate,
  validateFavoriteTripPatch,
  validateSavedPlaceCreate,
  validateSavedPlacePatch,
  validateScheduledRideCreate,
  validateScheduledRideListQuery,
} from "./taxi.loyalty.validators.js";

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

function requireEntityId(req, res, field, paramName = "id") {
  const v = validateEntityId(req.params?.[paramName], field);
  if (!v.ok) {
    badRequest(res, v.errors);
    return null;
  }
  return v.value;
}

export async function listSavedPlaces(req, res, next) {
  try {
    const items = await loyaltyService.listSavedPlaces(req.userId);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function createSavedPlace(req, res, next) {
  try {
    const v = validateSavedPlaceCreate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.createSavedPlace(req.userId, v.value);
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function updateSavedPlace(req, res, next) {
  try {
    const placeId = requireEntityId(req, res, "savedPlaceId");
    if (!placeId) return;
    const v = validateSavedPlacePatch(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.updateSavedPlace(req.userId, placeId, v.value);
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function deleteSavedPlace(req, res, next) {
  try {
    const placeId = requireEntityId(req, res, "savedPlaceId");
    if (!placeId) return;
    const out = await loyaltyService.deleteSavedPlace(req.userId, placeId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function importSavedPlaces(req, res, next) {
  try {
    const out = await loyaltyService.importSavedPlacesFromCustomerAddresses(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listFavoriteTrips(req, res, next) {
  try {
    const items = await loyaltyService.listFavoriteTrips(req.userId);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function createFavoriteTrip(req, res, next) {
  try {
    const v = validateFavoriteTripCreate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.createFavoriteTrip(req.userId, v.value);
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function updateFavoriteTrip(req, res, next) {
  try {
    const favoriteTripId = requireEntityId(req, res, "favoriteTripId");
    if (!favoriteTripId) return;
    const v = validateFavoriteTripPatch(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.updateFavoriteTrip(
      req.userId,
      favoriteTripId,
      v.value
    );
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function deleteFavoriteTrip(req, res, next) {
  try {
    const favoriteTripId = requireEntityId(req, res, "favoriteTripId");
    if (!favoriteTripId) return;
    const out = await loyaltyService.deleteFavoriteTrip(req.userId, favoriteTripId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listScheduledRides(req, res, next) {
  try {
    const v = validateScheduledRideListQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const items = await loyaltyService.listScheduledRides(req.userId, v.value);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function createScheduledRide(req, res, next) {
  try {
    const v = validateScheduledRideCreate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.createScheduledRide(req.userId, v.value);
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function cancelScheduledRide(req, res, next) {
  try {
    const scheduledRideId = requireEntityId(req, res, "scheduledRideId");
    if (!scheduledRideId) return;
    const item = await loyaltyService.cancelScheduledRide(req.userId, scheduledRideId);
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function listMyCoupons(req, res, next) {
  try {
    const items = await loyaltyService.listMyCoupons(req.userId);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function previewCoupon(req, res, next) {
  try {
    const v = validateCouponPreview(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const preview = await loyaltyService.previewCouponForUser({
      userId: req.userId,
      couponCode: v.value.couponCode,
      proposedFareIqd: v.value.proposedFareIqd,
    });
    return res.json(preview);
  } catch (error) {
    return next(error);
  }
}

export async function getRideComplaintEligibility(req, res, next) {
  try {
    const rideId = requireEntityId(req, res, "rideId", "rideId");
    if (!rideId) return;
    const out = await loyaltyService.getComplaintEligibility({
      rideId,
      riderUserId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createComplaint(req, res, next) {
  try {
    const v = validateComplaintCreate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.createCaptainComplaint({
      riderUserId: req.userId,
      tripId: v.value.tripId,
      category: v.value.category,
      reason: v.value.reason,
      details: v.value.details,
      attachmentUrl: v.value.attachmentUrl,
    });
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function listMyComplaints(req, res, next) {
  try {
    const limit = Number(req.query?.limit || 80);
    const items = await loyaltyService.listRiderComplaints(req.userId, { limit });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function rateRiderByCaptain(req, res, next) {
  try {
    const rideId = requireEntityId(req, res, "rideId", "rideId");
    if (!rideId) return;
    const v = validateCaptainRiderRating(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.rateRiderByCaptain({
      rideId,
      captainUserId: req.userId,
      rating: v.value.rating,
      category: v.value.category,
      note: v.value.note,
    });
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function captainSubscriptionLedger(req, res, next) {
  try {
    const dashboard = await loyaltyService.listCaptainLoyaltyDashboard(req.userId, {
      limit: Number(req.query?.limit || 80),
    });
    return res.json({
      summary: dashboard.summary,
      ledger: dashboard.ledger,
    });
  } catch (error) {
    return next(error);
  }
}

export async function captainContests(req, res, next) {
  try {
    const shouldRefresh =
      String(req.query?.refresh || "").trim().toLowerCase() === "true";
    if (shouldRefresh) {
      await loyaltyService.refreshCaptainContestProgress(req.userId);
    }
    const dashboard = await loyaltyService.listCaptainLoyaltyDashboard(req.userId, {
      limit: Number(req.query?.limit || 80),
    });
    return res.json({
      contests: dashboard.contests,
      rewards: dashboard.rewards,
    });
  } catch (error) {
    return next(error);
  }
}

export async function captainRewards(req, res, next) {
  try {
    const dashboard = await loyaltyService.listCaptainLoyaltyDashboard(req.userId, {
      limit: Number(req.query?.limit || 80),
    });
    return res.json({
      rewards: dashboard.rewards,
    });
  } catch (error) {
    return next(error);
  }
}

export async function captainGovernanceStatus(req, res, next) {
  try {
    const dashboard = await loyaltyService.listCaptainLoyaltyDashboard(req.userId, {
      limit: 50,
    });
    return res.json({
      governance: dashboard.governance,
      warnings: dashboard.warnings,
    });
  } catch (error) {
    return next(error);
  }
}

