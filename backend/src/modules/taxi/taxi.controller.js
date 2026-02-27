import {
  addUserStream,
  removeUserStream,
} from "../../shared/realtime/live-events.js";
import * as service from "./taxi.service.js";
import {
  validateBidId,
  validateCaptainPresence,
  validateCreateBid,
  validateCreateRide,
  validateHistoryQuery,
  validateLocationUpdate,
  validateNearbyQuery,
  validateRideId,
  validateShareToken,
} from "./taxi.validators.js";

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

function requireRideId(req, res) {
  const v = validateRideId(req.params.rideId);
  if (!v.ok) {
    badRequest(res, v.errors);
    return null;
  }
  return v.value;
}

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

export async function getCurrentRideForCustomer(req, res, next) {
  try {
    const out = await service.getCurrentRideForCustomer(req.userId);
    return res.json({ ride: out });
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

export async function publicTrack(req, res, next) {
  try {
    const v = validateShareToken(req.params.token);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getPublicTrack(v.value);
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

export function stream(req, res, next) {
  try {
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const writeEvent = (event, data) => {
      const payload = JSON.stringify(data || {});
      res.write(`event: ${event}\n`);
      res.write(`data: ${payload}\n\n`);
    };

    addUserStream(req.userId, res);
    writeEvent("connected", { at: new Date().toISOString(), module: "taxi" });

    const heartbeat = setInterval(() => {
      writeEvent("heartbeat", { at: new Date().toISOString() });
    }, 20000);

    req.on("close", () => {
      clearInterval(heartbeat);
      removeUserStream(req.userId, res);
    });
  } catch (error) {
    next(error);
  }
}
