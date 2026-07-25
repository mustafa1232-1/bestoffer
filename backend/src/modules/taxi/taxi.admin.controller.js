import * as loyaltyService from "./taxi.loyalty.service.js";
import * as service from "./taxi.service.js";
import {
  validateCaptainGiftBody,
  validateCaptainStatusBody,
  validateCaptainWarningBody,
  validateComplaintReviewBody,
  validateContestUpsertBody,
  validateCouponUpsertBody,
  validateKpiQuery,
  validateLookupQuery,
  validateReportQuery,
} from "./taxi.admin.validators.js";
import { validateEntityId } from "./taxi.loyalty.validators.js";
import { validateEmergencyCancel } from "./taxi.validators.js";

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

function actorFromReq(req) {
  return {
    userId: req.userId,
    userRole: req.userRole,
    userIsSuperAdmin: req.userIsSuperAdmin === true,
  };
}

export async function listCoupons(req, res, next) {
  try {
    const items = await loyaltyService.adminListCoupons(actorFromReq(req), req.query || {});
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function createCoupon(req, res, next) {
  try {
    const v = validateCouponUpsertBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminCreateCoupon(actorFromReq(req), v.value);
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function updateCoupon(req, res, next) {
  try {
    const couponId = requireEntityId(req, res, "couponId");
    if (!couponId) return;
    const v = validateCouponUpsertBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminUpdateCoupon(
      actorFromReq(req),
      couponId,
      v.value
    );
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function deleteCoupon(req, res, next) {
  try {
    const couponId = requireEntityId(req, res, "couponId");
    if (!couponId) return;
    const out = await loyaltyService.adminDeleteCoupon(actorFromReq(req), couponId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function couponTargetLookups(req, res, next) {
  try {
    const v = validateLookupQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await loyaltyService.adminCouponTargetLookups(actorFromReq(req), v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function captainDetails(req, res, next) {
  try {
    const captainUserId = requireEntityId(req, res, "captainUserId", "captainUserId");
    if (!captainUserId) return;
    const details = await loyaltyService.adminCaptainDetails(
      actorFromReq(req),
      captainUserId
    );
    return res.json(details);
  } catch (error) {
    return next(error);
  }
}

export async function issueCaptainGift(req, res, next) {
  try {
    const captainUserId = requireEntityId(req, res, "captainUserId", "captainUserId");
    if (!captainUserId) return;
    const v = validateCaptainGiftBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminIssueCaptainGift(
      actorFromReq(req),
      captainUserId,
      v.value
    );
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function issueCaptainWarning(req, res, next) {
  try {
    const captainUserId = requireEntityId(req, res, "captainUserId", "captainUserId");
    if (!captainUserId) return;
    const v = validateCaptainWarningBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminIssueCaptainWarning(
      actorFromReq(req),
      captainUserId,
      v.value
    );
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function setCaptainStatus(req, res, next) {
  try {
    const captainUserId = requireEntityId(req, res, "captainUserId", "captainUserId");
    if (!captainUserId) return;
    const v = validateCaptainStatusBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminSetCaptainStatus(
      actorFromReq(req),
      captainUserId,
      v.value
    );
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function listComplaints(req, res, next) {
  try {
    const items = await loyaltyService.adminListComplaints(actorFromReq(req), req.query || {});
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function reviewComplaint(req, res, next) {
  try {
    const complaintId = requireEntityId(req, res, "complaintId", "complaintId");
    if (!complaintId) return;
    const v = validateComplaintReviewBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminReviewComplaint(
      actorFromReq(req),
      complaintId,
      v.value
    );
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function listRideEmergencies(req, res, next) {
  try {
    const status =
      typeof req.query?.status === "string" && req.query.status.trim()
        ? req.query.status.trim()
        : null;
    const items = await service.listRideEmergencies({ status });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function emergencyCancelRide(req, res, next) {
  try {
    const rideId = requireEntityId(req, res, "rideId", "rideId");
    if (!rideId) return;
    const v = validateEmergencyCancel(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const ride = await service.adminEmergencyCancelRide({
      adminUserId: req.userId,
      rideId,
      reasonText: v.value.reasonText,
      secondApproverUserId: v.value.secondApproverUserId,
    });
    return res.json({ ride });
  } catch (error) {
    return next(error);
  }
}

export async function listContests(req, res, next) {
  try {
    const items = await loyaltyService.adminListContests(actorFromReq(req), req.query || {});
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function createContest(req, res, next) {
  try {
    const v = validateContestUpsertBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminCreateContest(actorFromReq(req), v.value);
    return res.status(201).json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function updateContest(req, res, next) {
  try {
    const contestId = requireEntityId(req, res, "contestId", "contestId");
    if (!contestId) return;
    const v = validateContestUpsertBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const item = await loyaltyService.adminUpdateContest(
      actorFromReq(req),
      contestId,
      v.value
    );
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function deleteContest(req, res, next) {
  try {
    const contestId = requireEntityId(req, res, "contestId", "contestId");
    if (!contestId) return;
    const out = await loyaltyService.adminDeleteContest(actorFromReq(req), contestId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function finalizeContest(req, res, next) {
  try {
    const contestId = requireEntityId(req, res, "contestId", "contestId");
    if (!contestId) return;
    const item = await loyaltyService.adminFinalizeContest(actorFromReq(req), contestId);
    return res.json({ item });
  } catch (error) {
    return next(error);
  }
}

export async function kpiOverview(req, res, next) {
  try {
    const v = validateKpiQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await loyaltyService.adminTaxiKpiOverview(actorFromReq(req), v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function reports(req, res, next) {
  try {
    const v = validateReportQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await loyaltyService.adminTaxiReports(actorFromReq(req), v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
