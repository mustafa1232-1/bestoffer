import { createNotification } from "../notifications/notifications.repo.js";
import { emitToUser } from "../../shared/realtime/live-events.js";
import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./taxi.repo.js";

function asInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function isCaptainRole(role) {
  return role === "delivery";
}

function ensureRideAccess({ ride, userId, role, isSuperAdmin }) {
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  if (isSuperAdmin === true || role === "admin" || role === "deputy_admin") {
    return;
  }

  if (role === "user" && ride.customerUserId === Number(userId)) return;
  if (isCaptainRole(role) && ride.assignedCaptainUserId === Number(userId)) return;

  throw new AppError("TAXI_RIDE_FORBIDDEN", { status: 403 });
}

function buildCompactRidePayload(ride) {
  return {
    id: ride.id,
    status: ride.status,
    proposedFareIqd: ride.proposedFareIqd,
    agreedFareIqd: ride.agreedFareIqd,
    pickup: ride.pickup,
    dropoff: ride.dropoff,
    customerUserId: ride.customerUserId,
    assignedCaptainUserId: ride.assignedCaptainUserId,
    createdAt: ride.createdAt,
    updatedAt: ride.updatedAt,
  };
}

function queueNotification(payload) {
  createNotification(payload).catch((error) => {
    console.warn("[taxi] notification queue failed", error?.message || error);
  });
}

function queueNotifications(payloads = []) {
  for (const payload of payloads) {
    queueNotification(payload);
  }
}

async function emitRideUpdate(ride, eventType, extra = {}) {
  if (!ride) return;

  const payload = {
    eventType,
    ride: buildCompactRidePayload(ride),
    ...extra,
  };

  emitToUser(ride.customerUserId, "taxi_ride_update", payload);
  if (ride.assignedCaptainUserId) {
    emitToUser(ride.assignedCaptainUserId, "taxi_ride_update", payload);
  }
}

async function markExpiredRidesAndEmit() {
  const expired = await repo.expireSearchingRides();
  for (const row of expired) {
    emitToUser(row.customerUserId, "taxi_ride_update", {
      eventType: "ride_expired",
      ride: {
        id: row.id,
        status: "expired",
      },
    });

    queueNotification({
      userId: row.customerUserId,
      type: "taxi.ride.expired",
      title: "انتهى وقت البحث عن كابتن",
      body: "لم يتم قبول الطلب ضمن الوقت المحدد، يمكنك إنشاء طلب جديد بسعر مختلف.",
      payload: {
        rideId: row.id,
        status: "expired",
      },
    });
  }
}

export async function createRideRequest(customerUserId, dto) {
  await markExpiredRidesAndEmit();

  const current = await repo.getCustomerCurrentRide(customerUserId);
  if (current) {
    throw new AppError("TAXI_ACTIVE_RIDE_EXISTS", { status: 409 });
  }

  const ride = await repo.createRideRequest({
    customerUserId,
    pickupLatitude: dto.pickupLatitude,
    pickupLongitude: dto.pickupLongitude,
    dropoffLatitude: dto.dropoffLatitude,
    dropoffLongitude: dto.dropoffLongitude,
    pickupLabel: dto.pickupLabel,
    dropoffLabel: dto.dropoffLabel,
    proposedFareIqd: dto.proposedFareIqd,
    searchRadiusM: dto.searchRadiusM,
    note: dto.note,
  });

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "ride_created",
    message: "تم إنشاء طلب تكسي جديد.",
    payload: {
      proposedFareIqd: ride.proposedFareIqd,
      searchRadiusM: ride.searchRadiusM,
    },
  });

  const nearbyCaptains = await repo.listNearbyCaptainsForPickup({
    pickupLatitude: ride.pickup.latitude,
    pickupLongitude: ride.pickup.longitude,
    radiusM: ride.searchRadiusM,
    limit: 60,
  });

  for (const captain of nearbyCaptains) {
    emitToUser(captain.captainUserId, "taxi_new_request", {
      ride: buildCompactRidePayload(ride),
      distanceM: captain.distanceM,
    });
  }

  queueNotifications(
    nearbyCaptains.map((captain) => ({
      userId: captain.captainUserId,
      type: "taxi.request.new",
      title: "طلب تكسي قريب منك",
      body: `سعر مقترح ${ride.proposedFareIqd} د.ع`,
      payload: {
        rideId: ride.id,
        proposedFareIqd: ride.proposedFareIqd,
      },
    }))
  );

  return {
    ride,
    nearbyCaptainsCount: nearbyCaptains.length,
  };
}

export async function getCurrentRideForCustomer(customerUserId) {
  await markExpiredRidesAndEmit();

  const ride = await repo.getCustomerCurrentRide(customerUserId);
  if (!ride) return null;

  const [bids, latestLocation, events] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 60 }),
  ]);

  return {
    ride,
    bids,
    latestLocation,
    events: [...events].reverse(),
  };
}

export async function getCurrentRideForCaptain(captainUserId) {
  await markExpiredRidesAndEmit();

  const ride = await repo.getCaptainCurrentRide(captainUserId);
  if (!ride) return null;

  const [bids, latestLocation, events] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 60 }),
  ]);

  return {
    ride,
    bids,
    latestLocation,
    events: [...events].reverse(),
  };
}

export async function getRideDetails({ rideId, userId, role, isSuperAdmin }) {
  await markExpiredRidesAndEmit();

  const ride = await repo.getRideById(rideId);
  ensureRideAccess({ ride, userId, role, isSuperAdmin });

  const [bids, latestLocation, events] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 120 }),
  ]);

  return {
    ride,
    bids,
    latestLocation,
    events: [...events].reverse(),
  };
}

export async function updateCaptainPresence(captainUserId, dto) {
  const presence = await repo.upsertCaptainPresence({
    captainUserId,
    isOnline: dto.isOnline,
    latitude: dto.latitude,
    longitude: dto.longitude,
    headingDeg: dto.headingDeg,
    speedKmh: dto.speedKmh,
    accuracyM: dto.accuracyM,
  });

  let nearbyRequests = [];
  if (presence.isOnline && presence.latitude != null && presence.longitude != null) {
    nearbyRequests = await repo.listNearbyOpenRidesForCaptain(captainUserId, {
      radiusM: dto.radiusM || 3000,
      limit: 30,
    });
  }

  return {
    presence,
    nearbyRequests,
  };
}

export async function listNearbyRequestsForCaptain(captainUserId, query) {
  await markExpiredRidesAndEmit();

  const items = await repo.listNearbyOpenRidesForCaptain(captainUserId, {
    radiusM: query.radiusM,
    limit: query.limit,
  });

  return {
    items,
    total: items.length,
  };
}

export async function submitBid({ captainUserId, rideId, dto }) {
  await markExpiredRidesAndEmit();

  const ride = await repo.getRideById(rideId);
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  if (ride.status !== "searching") {
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }

  if (ride.customerUserId === Number(captainUserId)) {
    throw new AppError("TAXI_SELF_BID_NOT_ALLOWED", { status: 403 });
  }

  const nearbyItems = await repo.listNearbyOpenRidesForCaptain(captainUserId, {
    radiusM: Math.max(ride.searchRadiusM, 2000),
    limit: 200,
  });

  const visibleToCaptain = nearbyItems.some((item) => item.id === ride.id);
  if (!visibleToCaptain) {
    throw new AppError("TAXI_RIDE_OUT_OF_RANGE", { status: 403 });
  }

  const bid = await repo.upsertRideBid({
    rideRequestId: ride.id,
    captainUserId,
    offeredFareIqd: dto.offeredFareIqd,
    etaMinutes: dto.etaMinutes,
    note: dto.note,
  });

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: captainUserId,
    eventType: "bid_submitted",
    message: "تم إرسال عرض من كابتن.",
    payload: {
      bidId: bid.id,
      offeredFareIqd: bid.offeredFareIqd,
      etaMinutes: bid.etaMinutes,
    },
  });

  emitToUser(ride.customerUserId, "taxi_bid_update", {
    eventType: "bid_submitted",
    rideId: ride.id,
    bid,
  });

  queueNotification({
    userId: ride.customerUserId,
    type: "taxi.bid.submitted",
    title: "وصل عرض جديد على طلبك",
    body: `عرض ${bid.offeredFareIqd} د.ع`,
    payload: {
      rideId: ride.id,
      bidId: bid.id,
      offeredFareIqd: bid.offeredFareIqd,
      etaMinutes: bid.etaMinutes,
    },
  });

  return {
    rideId: ride.id,
    bid,
  };
}

export async function acceptBid({ customerUserId, rideId, bidId }) {
  const result = await repo.acceptRideBid({
    rideId,
    bidId,
    customerUserId,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "BID_NOT_FOUND") {
      throw new AppError("TAXI_BID_NOT_FOUND", { status: 404 });
    }
    if (result.code === "BID_NOT_ACTIVE") {
      throw new AppError("TAXI_BID_NOT_ACTIVE", { status: 409 });
    }
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }

  const ride = result.ride;

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "bid_accepted",
    message: "تم قبول عرض الكابتن.",
    payload: {
      acceptedBidId: ride.acceptedBidId,
      assignedCaptainUserId: ride.assignedCaptainUserId,
      agreedFareIqd: ride.agreedFareIqd,
    },
  });

  await emitRideUpdate(ride, "bid_accepted", {
    acceptedBidId: ride.acceptedBidId,
  });

  const accepted = result.bids.find((b) => b.status === "accepted");
  if (accepted?.captainUserId) {
    queueNotification({
      userId: accepted.captainUserId,
      type: "taxi.bid.accepted",
      title: "تم قبول عرضك",
      body: `الزبون وافق على ${ride.agreedFareIqd || ride.proposedFareIqd} د.ع`,
      payload: {
        rideId: ride.id,
        bidId: accepted.id,
        agreedFareIqd: ride.agreedFareIqd,
      },
    });
  }

  const rejectionPayloads = [];
  for (const bid of result.bids) {
    if (bid.status !== "rejected") continue;
    rejectionPayloads.push({
      userId: bid.captainUserId,
      type: "taxi.bid.rejected",
      title: "تم اختيار كابتن آخر",
      body: "يمكنك متابعة الطلبات القريبة الجديدة.",
      payload: {
        rideId: ride.id,
        bidId: bid.id,
      },
    });
  }
  queueNotifications(rejectionPayloads);

  return {
    ride,
    bids: await repo.listRideBids(ride.id),
  };
}

export async function cancelRide({ customerUserId, rideId }) {
  const result = await repo.cancelRide({
    rideId,
    customerUserId,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    throw new AppError("TAXI_RIDE_ALREADY_CLOSED", { status: 409 });
  }

  await repo.createRideEvent({
    rideRequestId: result.ride.id,
    actorUserId: customerUserId,
    eventType: "ride_cancelled",
    message: "تم إلغاء الطلب من قبل الزبون.",
    payload: null,
  });

  await emitRideUpdate(result.ride, "ride_cancelled");

  if (result.ride.assignedCaptainUserId) {
    queueNotification({
      userId: result.ride.assignedCaptainUserId,
      type: "taxi.ride.cancelled",
      title: "تم إلغاء الطلب",
      body: "الزبون ألغى الرحلة قبل الإتمام.",
      payload: {
        rideId: result.ride.id,
      },
    });
  }

  return result.ride;
}

async function transitionRideStatus({ captainUserId, rideId, nextStatus, eventType, notificationBody }) {
  const result = await repo.transitionRideStatus({
    rideId,
    captainUserId,
    nextStatus,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "RIDE_NOT_ASSIGNED_TO_CAPTAIN") {
      throw new AppError("TAXI_RIDE_NOT_ASSIGNED_TO_CAPTAIN", { status: 403 });
    }
    throw new AppError("TAXI_INVALID_STATUS_TRANSITION", {
      status: 409,
      details: { currentStatus: result.currentStatus },
    });
  }

  await repo.createRideEvent({
    rideRequestId: result.ride.id,
    actorUserId: captainUserId,
    eventType,
    message: notificationBody,
    payload: {
      previousStatus: result.previousStatus,
      nextStatus,
    },
  });

  await emitRideUpdate(result.ride, eventType, {
    previousStatus: result.previousStatus,
  });

  queueNotification({
    userId: result.ride.customerUserId,
    type: `taxi.ride.${eventType}`,
    title: "تحديث على رحلة التكسي",
    body: notificationBody,
    payload: {
      rideId: result.ride.id,
      status: result.ride.status,
    },
  });

  return result.ride;
}

export async function markCaptainArrived({ captainUserId, rideId }) {
  return transitionRideStatus({
    captainUserId,
    rideId,
    nextStatus: "captain_arriving",
    eventType: "captain_arriving",
    notificationBody: "الكابتن في طريقه إليك الآن.",
  });
}

export async function startRide({ captainUserId, rideId }) {
  return transitionRideStatus({
    captainUserId,
    rideId,
    nextStatus: "ride_started",
    eventType: "ride_started",
    notificationBody: "بدأت الرحلة، يمكنك متابعة السيارة مباشرة.",
  });
}

export async function completeRide({ captainUserId, rideId }) {
  const ride = await transitionRideStatus({
    captainUserId,
    rideId,
    nextStatus: "completed",
    eventType: "ride_completed",
    notificationBody: "تم إكمال الرحلة بنجاح.",
  });

  queueNotification({
    userId: captainUserId,
    type: "taxi.ride.completed",
    title: "تم إنهاء الرحلة",
    body: "تم تسجيل الرحلة كمكتملة.",
    payload: {
      rideId: ride.id,
      status: ride.status,
    },
  });

  return ride;
}

export async function updateRideLocation({ captainUserId, rideId, dto }) {
  const result = await repo.insertRideLocation({
    rideId,
    captainUserId,
    latitude: dto.latitude,
    longitude: dto.longitude,
    headingDeg: dto.headingDeg,
    speedKmh: dto.speedKmh,
    accuracyM: dto.accuracyM,
    source: "captain_app",
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "RIDE_NOT_ASSIGNED_TO_CAPTAIN") {
      throw new AppError("TAXI_RIDE_NOT_ASSIGNED_TO_CAPTAIN", { status: 403 });
    }
    throw new AppError("TAXI_RIDE_NOT_TRACKABLE", {
      status: 409,
      details: { currentStatus: result.currentStatus },
    });
  }

  const ride = await repo.getRideById(rideId);
  if (ride) {
    emitToUser(ride.customerUserId, "taxi_location_update", {
      rideId: ride.id,
      status: ride.status,
      location: result.location,
    });

    if (ride.assignedCaptainUserId) {
      emitToUser(ride.assignedCaptainUserId, "taxi_location_update", {
        rideId: ride.id,
        status: ride.status,
        location: result.location,
      });
    }
  }

  return {
    ride,
    location: result.location,
  };
}

export async function createShareToken({ customerUserId, rideId }) {
  const ride = await repo.getRideByIdForCustomer(rideId, customerUserId);
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  const token = await repo.generateShareToken();
  const out = await repo.upsertRideShareToken({
    rideId,
    customerUserId,
    token,
  });

  if (!out) {
    throw new AppError("TAXI_SHARE_NOT_AVAILABLE", { status: 409 });
  }

  return out;
}

export async function getPublicTrack(token) {
  const data = await repo.getPublicTrackByToken(token);
  if (!data) {
    throw new AppError("TAXI_TRACK_NOT_FOUND", { status: 404 });
  }

  const events = await repo.listRideEvents(data.ride.id, { limit: 50 });

  return {
    ride: data.ride,
    latestLocation: data.location,
    events: [...events].reverse(),
  };
}

export async function listCaptainHistory(captainUserId, query) {
  const items = await repo.listCaptainRideHistory(captainUserId, {
    limit: query.limit,
  });
  return {
    items,
    total: items.length,
  };
}
