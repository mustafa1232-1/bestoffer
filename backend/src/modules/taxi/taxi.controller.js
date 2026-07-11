import {
  addUserStream,
  getLatestUserEventId,
  replayUserEvents,
  removeUserStream,
  writeSseEvent,
} from "../../shared/realtime/live-events.js";
import * as service from "./taxi.service.js";
import {
  validateCaptainProfileEditRequest,
  validateBidId,
  validateCaptainPresence,
  validateCounterOffer,
  validateCreateBid,
  validateCreateRide,
  validateFriendRideShareBody,
  validateRideRating,
  validateRideChatMessage,
  validateRideChatQuery,
  validateRideCallEnd,
  validateRideCallSignal,
  validateRideCallStateQuery,
  validateHistoryQuery,
  validateLocationUpdate,
  validateNearbyCaptainsQuery,
  validateNearbyQuery,
  validateRideId,
} from "./taxi.validators.js";

/**
 * Purpose:
 * controllers التاكسي. تطبق validation وتطبع المدخلات ثم تمرر التنفيذ إلى
 * `taxi.service.js` مع response shape موحد.
 *
 * Used by:
 * - `taxi.routes.js`
 */

/**
 * helper موحد لرد validation error بصيغة متسقة.
 */
function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

/**
 * يقرأ `rideId` من params ويتأكد من صلاحيته قبل المرور إلى service.
 */
function requireRideId(req, res) {
  const v = validateRideId(req.params.rideId);
  if (!v.ok) {
    badRequest(res, v.errors);
    return null;
  }
  return v.value;
}

function validateShareTokenParam(token) {
  const value = String(token || "").trim();
  if (value.length < 8 || value.length > 160) {
    return { ok: false, errors: ["token"] };
  }
  return { ok: true, value };
}

/**
 * ينشئ طلب رحلة جديداً للعميل الحالي.
 */
export async function createRide(req, res, next) {
  try {
    const v = validateCreateRide(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.createRideRequest(req.userId, v.value);
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

/**
 * يجلب الرحلة الحالية للعميل إذا كانت موجودة.
 */
export async function getCurrentRideForCustomer(req, res, next) {
  try {
    const out = await service.getCurrentRideForCustomer(req.userId);
    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function listMyRideHistory(req, res, next) {
  try {
    const v = validateHistoryQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const items = await service.listCustomerRideHistory(req.userId, v.value);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function listNearbyCaptains(req, res, next) {
  try {
    const v = validateNearbyCaptainsQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listNearbyCaptainsForCustomer(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getCurrentRideForCaptain(req, res, next) {
  try {
    const out = await service.getCurrentRideForCaptain(req.userId);
    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function getRideDetails(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.getRideDetails({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function cancelRide(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.cancelRide({
      customerUserId: req.userId,
      rideId,
    });

    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function rebookRide(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.rebookRideByCustomer({
      customerUserId: req.userId,
      rideId,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function rateRide(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideRating(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.rateRideByCustomer({
      customerUserId: req.userId,
      rideId,
      dto: v.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const bid = validateBidId(req.params.bidId);
    if (!bid.ok) return badRequest(res, bid.errors);

    const out = await service.acceptBid({
      customerUserId: req.userId,
      rideId,
      bidId: bid.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptCustomerFare(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.acceptRideByCaptain({
      captainUserId: req.userId,
      rideId,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function rejectCurrentBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.rejectCurrentBid({
      customerUserId: req.userId,
      rideId,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function counterOfferCurrentBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateCounterOffer(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.counterOfferCurrentBid({
      customerUserId: req.userId,
      rideId,
      dto: v.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

/**
 * ينفذ bid جديد من جهة الكابتن.
 */
export async function rejectBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const bid = validateBidId(req.params.bidId);
    if (!bid.ok) return badRequest(res, bid.errors);

    const out = await service.rejectCurrentBid({
      customerUserId: req.userId,
      rideId,
      bidId: bid.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function counterOfferBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const bid = validateBidId(req.params.bidId);
    if (!bid.ok) return badRequest(res, bid.errors);

    const v = validateCounterOffer(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.counterOfferCurrentBid({
      customerUserId: req.userId,
      rideId,
      bidId: bid.value,
      dto: v.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createBid(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateCreateBid(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.submitBid({
      captainUserId: req.userId,
      rideId,
      dto: v.value,
    });

    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function declineRideByCaptain(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.declineRideRequestByCaptain({
      captainUserId: req.userId,
      rideId,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

/**
 * يحدث presence وموقع الكابتن الحالي.
 */
export async function upsertPresence(req, res, next) {
  try {
    const v = validateCaptainPresence(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.updateCaptainPresence(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listNearbyRequests(req, res, next) {
  try {
    const v = validateNearbyQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listNearbyRequestsForCaptain(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function markArrived(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.markCaptainArrived({
      captainUserId: req.userId,
      rideId,
    });

    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function startRide(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.startRide({
      captainUserId: req.userId,
      rideId,
    });

    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function completeRide(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.completeRide({
      captainUserId: req.userId,
      rideId,
    });

    return res.json({ ride: out });
  } catch (error) {
    return next(error);
  }
}

export async function updateLocation(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateLocationUpdate(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.updateRideLocation({
      captainUserId: req.userId,
      rideId,
      dto: v.value,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createShareToken(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.createShareToken({
      customerUserId: req.userId,
      rideId,
    });

    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listRideChat(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideChatQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listRideChatMessages({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
      limit: v.value.limit,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendRideChat(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideChatMessage(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.sendRideChatMessage({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
      dto: v.value,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getRideCallState(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideCallStateQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getRideCallState({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
      signalLimit: v.value.signalLimit,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function startRideCall(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.startRideCall({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendRideCallSignal(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideCallSignal(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.sendRideCallSignal({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
      dto: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function endRideCall(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateRideCallEnd(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.endRideCall({
      rideId,
      userId: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin,
      dto: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function publicTrack(req, res, next) {
  try {
    const v = validateShareTokenParam(req.params.token);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getPublicTrack(v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function publicTrackStream(req, res, next) {
  try {
    const v = validateShareTokenParam(req.params.token);
    if (!v.ok) return badRequest(res, v.errors);

    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const token = v.value;
    let lastSerialized = "";

    const pushSnapshot = async () => {
      const snapshot = await service.getPublicTrack(token);
      const serialized = JSON.stringify(snapshot || null);
      if (!snapshot) {
        writeSseEvent(res, "closed", {
          module: "taxi",
          reason: "TRACKING_NOT_FOUND",
          token,
        });
        return false;
      }
      if (serialized !== lastSerialized) {
        lastSerialized = serialized;
        writeSseEvent(res, "taxi_location_update", snapshot);
      }
      return true;
    };

    const initialOk = await pushSnapshot();
    if (!initialOk) {
      res.end();
      return;
    }

    const heartbeat = setInterval(() => {
      writeSseEvent(res, "heartbeat", {
        at: new Date().toISOString(),
        module: "taxi",
        token,
      });
    }, 20000);

    const poller = setInterval(async () => {
      try {
        const keepOpen = await pushSnapshot();
        if (!keepOpen) {
          clearInterval(heartbeat);
          clearInterval(poller);
          res.end();
        }
      } catch (_) {
        writeSseEvent(res, "resync_required", {
          module: "taxi",
          token,
        });
      }
    }, 3000);

    req.on("close", () => {
      clearInterval(heartbeat);
      clearInterval(poller);
    });
  } catch (error) {
    next(error);
  }
}

export async function listRideSharedFriends(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.listRideSharedFriends({
      customerUserId: req.userId,
      rideId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function shareRideWithFriends(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const v = validateFriendRideShareBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.shareRideWithFriends({
      customerUserId: req.userId,
      rideId,
      friendUserIds: v.value.friendUserIds,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getSharedRideTrack(req, res, next) {
  try {
    const rideId = requireRideId(req, res);
    if (!rideId) return;

    const out = await service.getSharedRideTrackForFriend({
      friendUserId: req.userId,
      rideId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCaptainHistory(req, res, next) {
  try {
    const v = validateHistoryQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listCaptainHistory(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getCaptainDashboard(req, res, next) {
  try {
    const v = validateHistoryQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getCaptainDashboard(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getCaptainProfile(req, res, next) {
  try {
    const out = await service.getCaptainProfile(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getCaptainSubscription(req, res, next) {
  try {
    const out = await service.getCaptainSubscriptionStatus(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function requestCaptainCashPayment(req, res, next) {
  try {
    const out = await service.requestCaptainCashPayment(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function requestCaptainProfileEdit(req, res, next) {
  try {
    const v = validateCaptainProfileEditRequest(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.requestCaptainProfileEdit({
      captainUserId: req.userId,
      dto: v.value,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export function stream(req, res, next) {
  try {
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const rawLastId = req.get("last-event-id") || req.query?.lastEventId;
    const lastEventId = Number(rawLastId || 0);
    const safeLastEventId =
      Number.isFinite(lastEventId) && lastEventId > 0
        ? Math.floor(lastEventId)
        : 0;

    addUserStream(req.userId, res, { channel: "taxi" });
    writeSseEvent(
      res,
      "connected",
      {
        at: new Date().toISOString(),
        module: "taxi",
        lastEventId: safeLastEventId || null,
      },
      { retry: 3000 }
    );

    if (safeLastEventId > 0) {
      const replay = replayUserEvents(req.userId, res, {
        afterEventId: safeLastEventId,
        maxEvents: 1000,
        channel: "taxi",
      });
      if (replay.resyncRequired) {
        writeSseEvent(res, "resync_required", {
          module: "taxi",
          reason: replay.reason,
          latestEventId: replay.latestEventId || null,
          oldestEventId: replay.oldestEventId || null,
        });
      } else if (replay.replayed > 0) {
        writeSseEvent(res, "replayed", {
          replayed: replay.replayed,
          lastEventId: replay.lastEventId,
          module: "taxi",
        });
      }
    }

    const heartbeat = setInterval(() => {
      writeSseEvent(
        res,
        "heartbeat",
        {
          at: new Date().toISOString(),
          module: "taxi",
          latestEventId: getLatestUserEventId(req.userId, { channel: "taxi" }),
        }
      );
    }, 20000);

    req.on("close", () => {
      clearInterval(heartbeat);
      removeUserStream(req.userId, res);
    });
  } catch (error) {
    next(error);
  }
}
