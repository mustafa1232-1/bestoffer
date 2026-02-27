import { createNotification } from "../notifications/notifications.repo.js";
import { emitToUser } from "../../shared/realtime/live-events.js";
import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./taxi.repo.js";

const FIRST_SEARCH_RADIUS_M = 2000;
const EXPANDED_SEARCH_RADIUS_M = 4000;
const SEARCH_STAGE_MINUTES = 5;
const CAPTAIN_SUBSCRIPTION_MONTHLY_FEE_IQD = 10000;

let lifecycleWorker = null;
let lifecycleRunning = false;

function addDays(dateInput, days) {
  const d = new Date(dateInput);
  d.setDate(d.getDate() + Number(days || 0));
  return d;
}

function calcDiscountedFee(monthlyFeeIqd, discountPercent) {
  const fee = Math.max(0, Number(monthlyFeeIqd) || CAPTAIN_SUBSCRIPTION_MONTHLY_FEE_IQD);
  const discount = Math.max(0, Math.min(100, Number(discountPercent) || 0));
  return Math.max(0, Math.round((fee * (100 - discount)) / 100));
}

function evaluateCaptainSubscription(raw) {
  const now = new Date();
  const trialDays = Math.max(0, Number(raw?.trial_days) || 30);
  const trialStartedAt = raw?.trial_started_at ? new Date(raw.trial_started_at) : now;
  const trialEndsAt = addDays(trialStartedAt, trialDays);

  const cycleStartAt = raw?.current_cycle_start_at
    ? new Date(raw.current_cycle_start_at)
    : null;
  const cycleEndsAt = raw?.current_cycle_end_at ? new Date(raw.current_cycle_end_at) : null;

  const isTrialActive = now <= trialEndsAt;
  const isCycleActive = cycleEndsAt != null && now <= cycleEndsAt;
  const canAccess = isTrialActive || isCycleActive;

  const activeEndsAt = isCycleActive ? cycleEndsAt : trialEndsAt;
  const remainingMs = Math.max(0, activeEndsAt.getTime() - now.getTime());
  const remainingDays = Math.ceil(remainingMs / (24 * 60 * 60 * 1000));

  const monthlyFeeIqd = Math.max(
    0,
    Number(raw?.monthly_fee_iqd) || CAPTAIN_SUBSCRIPTION_MONTHLY_FEE_IQD
  );
  const discountPercent = Math.max(0, Math.min(100, Number(raw?.discount_percent) || 0));
  const discountedMonthlyFeeIqd = calcDiscountedFee(monthlyFeeIqd, discountPercent);

  return {
    canAccess,
    phase: isTrialActive ? "trial" : isCycleActive ? "paid" : "expired",
    monthlyFeeIqd,
    discountPercent,
    discountedMonthlyFeeIqd,
    dueAmountIqd: canAccess ? 0 : discountedMonthlyFeeIqd,
    trialStartedAt,
    trialEndsAt,
    cycleStartAt,
    cycleEndsAt,
    activeEndsAt,
    remainingDays,
    cashPaymentPending: raw?.cash_payment_pending === true,
    cashPaymentRequestedAt: raw?.cash_payment_requested_at || null,
    lastCashPaymentConfirmedAt: raw?.last_cash_payment_confirmed_at || null,
    lastExpiryReminderOn: raw?.last_expiry_reminder_on || null,
  };
}

async function maybeSendCaptainSubscriptionReminder(captainUserId, profile, subscriptionStatus) {
  if (!subscriptionStatus?.canAccess) return;
  if (subscriptionStatus.remainingDays <= 0 || subscriptionStatus.remainingDays > 7) return;

  const today = new Date().toISOString().slice(0, 10);
  if (subscriptionStatus.lastExpiryReminderOn === today) return;

  const title = "تنبيه انتهاء اشتراك الكابتن";
  const body =
    subscriptionStatus.remainingDays === 1
      ? "باقي يوم واحد على انتهاء اشتراكك الشهري. راجع الإدارة للتسديد النقدي."
      : `باقي ${subscriptionStatus.remainingDays} أيام على انتهاء اشتراكك الشهري. راجع الإدارة للتسديد النقدي.`;

  queueNotification({
    userId: Number(captainUserId),
    type: "taxi.captain.subscription.expiry_reminder",
    title,
    body,
    payload: {
      remainingDays: subscriptionStatus.remainingDays,
      dueAmountIqd: subscriptionStatus.discountedMonthlyFeeIqd,
    },
  });

  await repo.updateCaptainSubscriptionReminderDate(captainUserId, today);
}

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

async function notifyCaptainsNearRide(ride) {
  if (!ride?.pickup) return 0;

  const nearbyCaptains = await repo.listNearbyCaptainsForPickup({
    pickupLatitude: ride.pickup.latitude,
    pickupLongitude: ride.pickup.longitude,
    radiusM: ride.searchRadiusM,
    limit: 80,
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
        searchRadiusM: ride.searchRadiusM,
      },
    }))
  );

  return nearbyCaptains.length;
}

async function processSearchingLifecycleAndEmit() {
  if (lifecycleRunning) return;
  lifecycleRunning = true;

  try {
    const due = await repo.listRidesReadyForSearchProgression({ limit: 120 });
    for (const ride of due) {
      if (!ride || ride.status !== "searching") continue;

      if ((ride.searchPhase || 1) <= 1) {
        const updated = await repo.advanceRideToExpandedSearch({
          rideId: ride.id,
          expandedRadiusM: EXPANDED_SEARCH_RADIUS_M,
        });
        if (!updated) continue;

        await repo.createRideEvent({
          rideRequestId: updated.id,
          actorUserId: updated.customerUserId,
          eventType: "search_expanded",
          message: "تم توسيع نطاق البحث عن كابتن إلى 4 كم.",
          payload: {
            searchRadiusM: updated.searchRadiusM,
            searchPhase: updated.searchPhase,
            windowMinutes: SEARCH_STAGE_MINUTES,
          },
        });

        const pushedCount = await notifyCaptainsNearRide(updated);
        await emitRideUpdate(updated, "search_expanded", {
          searchRadiusM: updated.searchRadiusM,
          nearbyCaptainsCount: pushedCount,
          windowMinutes: SEARCH_STAGE_MINUTES,
        });

        queueNotification({
          userId: updated.customerUserId,
          type: "taxi.ride.search_expanded",
          title: "وسعنا البحث عن كابتن",
          body: "تم توسيع نطاق البحث إلى 4 كم لمدة 5 دقائق إضافية.",
          payload: {
            rideId: updated.id,
            searchRadiusM: updated.searchRadiusM,
            searchPhase: updated.searchPhase,
          },
        });
        continue;
      }

      if (ride.searchPhase === 2) {
        const hasActiveBids = await repo.hasActiveBids(ride.id);
        if (hasActiveBids) {
          await repo.postponeRideEscalation({
            rideId: ride.id,
            minutes: SEARCH_STAGE_MINUTES,
          });
          continue;
        }

        const notified = await repo.markRideNoCaptainFound(ride.id);
        if (!notified) continue;

        await repo.createRideEvent({
          rideRequestId: notified.id,
          actorUserId: notified.customerUserId,
          eventType: "no_captain_found",
          message: "لم يتم العثور على كابتن متاح حاليًا.",
          payload: {
            searchRadiusM: notified.searchRadiusM,
            searchPhase: notified.searchPhase,
          },
        });

        await emitRideUpdate(notified, "no_captain_found", {
          searchRadiusM: notified.searchRadiusM,
          searchPhase: notified.searchPhase,
        });

        queueNotification({
          userId: notified.customerUserId,
          type: "taxi.ride.no_captain_found",
          title: "لا يوجد كابتن متاح الآن",
          body: "طلبك ما زال نشطًا. يمكنك تعديل السعر أو الانتظار حتى يتوفر كابتن.",
          payload: {
            rideId: notified.id,
            status: notified.status,
            searchPhase: notified.searchPhase,
          },
        });
      }
    }
  } catch (error) {
    console.warn("[taxi] lifecycle processing failed", error?.message || error);
  } finally {
    lifecycleRunning = false;
  }
}

export function startTaxiLifecycleWorker({ intervalMs = 20000 } = {}) {
  if (lifecycleWorker) return;

  lifecycleWorker = setInterval(() => {
    processSearchingLifecycleAndEmit().catch((error) => {
      console.warn("[taxi] worker tick failed", error?.message || error);
    });
  }, Math.max(5000, Number(intervalMs) || 20000));

  lifecycleWorker.unref?.();
  void processSearchingLifecycleAndEmit();
}

export async function createRideRequest(customerUserId, dto) {
  await processSearchingLifecycleAndEmit();

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
    searchRadiusM: FIRST_SEARCH_RADIUS_M,
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
      searchPhase: ride.searchPhase,
      windowMinutes: SEARCH_STAGE_MINUTES,
    },
  });

  const nearbyCaptainsCount = await notifyCaptainsNearRide(ride);

  return {
    ride,
    nearbyCaptainsCount,
  };
}

function mapCaptainProfile(row) {
  if (!row) return null;
  return {
    userId: Number(row.id),
    fullName: row.full_name || null,
    phone: row.phone || null,
    block: row.block || null,
    buildingNumber: row.building_number || null,
    apartment: row.apartment || null,
    imageUrl: row.image_url || null,
    createdAt: row.created_at || null,
    deliveryAccountApproved: row.delivery_account_approved === true,
    profileImageUrl: row.profile_image_url || null,
    carImageUrl: row.car_image_url || null,
    vehicleType: row.vehicle_type || null,
    carMake: row.car_make || null,
    carModel: row.car_model || null,
    carYear: row.car_year == null ? null : Number(row.car_year),
    carColor: row.car_color || null,
    plateNumber: row.plate_number || null,
    isActive: row.is_active === true,
    ratingAvg: row.rating_avg == null ? 0 : Number(row.rating_avg),
    ridesCount: row.rides_count == null ? 0 : Number(row.rides_count),
  };
}

function mapCaptainDashboardMetrics(row) {
  return {
    day: {
      ridesCount: Number(row?.day_completed_count || 0),
      earningsIqd: Number(row?.day_earnings_iqd || 0),
    },
    week: {
      ridesCount: Number(row?.week_completed_count || 0),
      earningsIqd: Number(row?.week_earnings_iqd || 0),
    },
    month: {
      ridesCount: Number(row?.month_completed_count || 0),
      earningsIqd: Number(row?.month_earnings_iqd || 0),
    },
    total: {
      ridesCount: Number(row?.total_rides_count || 0),
      earningsIqd: Number(row?.total_earnings_iqd || 0),
    },
  };
}

function sanitizeCaptainProfileEditChanges(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const out = {};
  const allowed = new Set([
    "fullName",
    "phone",
    "block",
    "buildingNumber",
    "apartment",
    "vehicleType",
    "carMake",
    "carModel",
    "carYear",
    "carColor",
    "plateNumber",
    "profileImageUrl",
    "carImageUrl",
  ]);

  for (const [key, rawValue] of Object.entries(source)) {
    if (!allowed.has(key)) continue;

    if (key === "carYear") {
      const n = Number(rawValue);
      if (Number.isInteger(n) && n >= 1950 && n <= 2100) {
        out[key] = n;
      }
      continue;
    }

    if (rawValue == null) continue;
    const text = String(rawValue).trim();
    if (!text) continue;
    out[key] = text.slice(0, 240);
  }

  return out;
}

async function loadCaptainSubscriptionContext(captainUserId) {
  const profileRow = await repo.getCaptainProfile(captainUserId);
  if (!profileRow) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  const raw = await repo.getCaptainSubscription(captainUserId);
  const subscription = evaluateCaptainSubscription(raw || {});
  await maybeSendCaptainSubscriptionReminder(
    captainUserId,
    profileRow,
    subscription
  );

  return {
    profile: mapCaptainProfile(profileRow),
    raw,
    subscription,
  };
}

export async function getCaptainSubscriptionStatus(captainUserId) {
  const ctx = await loadCaptainSubscriptionContext(captainUserId);
  return {
    profile: ctx.profile,
    subscription: ctx.subscription,
  };
}

export async function assertCaptainSubscriptionAccess(captainUserId) {
  const ctx = await loadCaptainSubscriptionContext(captainUserId);
  if (ctx.subscription.canAccess) {
    return ctx.subscription;
  }

  if (ctx.subscription.cashPaymentPending) {
    throw new AppError("DELIVERY_SUBSCRIPTION_PAYMENT_PENDING", {
      status: 403,
      details: {
        dueAmountIqd: ctx.subscription.discountedMonthlyFeeIqd,
      },
    });
  }

  throw new AppError("DELIVERY_SUBSCRIPTION_EXPIRED", {
    status: 403,
    details: {
      dueAmountIqd: ctx.subscription.discountedMonthlyFeeIqd,
    },
  });
}

export async function getCurrentRideForCustomer(customerUserId) {
  await processSearchingLifecycleAndEmit();

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
  await assertCaptainSubscriptionAccess(captainUserId);
  await processSearchingLifecycleAndEmit();

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
  await processSearchingLifecycleAndEmit();

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
  await assertCaptainSubscriptionAccess(captainUserId);
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
  await assertCaptainSubscriptionAccess(captainUserId);
  await processSearchingLifecycleAndEmit();

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
  await assertCaptainSubscriptionAccess(captainUserId);
  await processSearchingLifecycleAndEmit();

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
  await assertCaptainSubscriptionAccess(captainUserId);
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
  await assertCaptainSubscriptionAccess(captainUserId);
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
  const period = query?.period || "month";
  const items = await repo.listCaptainRideHistoryByPeriod(captainUserId, {
    period,
    limit: query.limit,
  });
  return {
    period,
    items,
    total: items.length,
  };
}

export async function getCaptainProfile(captainUserId) {
  const { profile, subscription } = await loadCaptainSubscriptionContext(
    captainUserId
  );
  return {
    profile,
    subscription,
  };
}

export async function requestCaptainProfileEdit({ captainUserId, dto }) {
  const current = await repo.getCaptainProfile(captainUserId);
  if (!current) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  const changes = sanitizeCaptainProfileEditChanges(dto?.requestedChanges || {});
  if (Object.keys(changes).length === 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["requestedChanges"] },
    });
  }

  const request = await repo.createCaptainProfileEditRequest({
    captainUserId,
    requestedChanges: changes,
    captainNote: dto?.captainNote || null,
  });

  const backofficeUsers = await repo.listBackofficeUsers();
  queueNotifications(
    backofficeUsers.map((userId) => ({
      userId,
      type: "taxi.captain.profile_edit.requested",
      title: "طلب تعديل بيانات كابتن تكسي",
      body: `${current.full_name || "كابتن"} أرسل طلب تعديل بيانات.`,
      payload: {
        requestId: Number(request?.id),
        captainUserId: Number(captainUserId),
      },
    }))
  );

  return {
    request,
  };
}

export async function getCaptainDashboard(captainUserId, query = {}) {
  const period = String(query?.period || "month").toLowerCase();
  const safePeriod = ["day", "week", "month", "all"].includes(period)
    ? period
    : "month";
  const limit = Math.max(1, Math.min(200, Number(query?.limit) || 40));

  const [profileRow, metricsRow, history, subscriptionRaw] = await Promise.all([
    repo.getCaptainProfile(captainUserId),
    repo.getCaptainDashboardMetrics(captainUserId),
    repo.listCaptainRideHistoryByPeriod(captainUserId, {
      period: safePeriod,
      limit,
    }),
    repo.getCaptainSubscription(captainUserId),
  ]);

  if (!profileRow) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  const subscription = evaluateCaptainSubscription(subscriptionRaw || {});
  await maybeSendCaptainSubscriptionReminder(
    captainUserId,
    profileRow,
    subscription
  );

  return {
    profile: mapCaptainProfile(profileRow),
    subscription,
    metrics: mapCaptainDashboardMetrics(metricsRow || {}),
    historyPeriod: safePeriod,
    history,
  };
}

export async function requestCaptainCashPayment(captainUserId) {
  const current = await repo.getCaptainProfile(captainUserId);
  if (!current) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  await repo.requestCaptainCashPayment(captainUserId);
  const { subscription } = await loadCaptainSubscriptionContext(captainUserId);

  const backofficeUsers = await repo.listBackofficeUsers();
  queueNotifications(
    backofficeUsers.map((userId) => ({
      userId,
      type: "taxi.captain.subscription.cash_payment_requested",
      title: "طلب تسديد اشتراك كابتن",
      body: `${current.full_name || "كابتن"} طلب تسديد نقدي لاشتراك التكسي.`,
      payload: {
        captainUserId: Number(captainUserId),
        dueAmountIqd: subscription.discountedMonthlyFeeIqd,
      },
    }))
  );

  return {
    subscription,
  };
}

export async function setCaptainDiscountByAdmin({
  captainUserId,
  discountPercent,
  adminUserId,
}) {
  const captain = await repo.getCaptainProfile(captainUserId);
  if (!captain) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  await repo.setCaptainDiscountPercent({
    captainUserId,
    discountPercent,
    updatedByUserId: adminUserId,
  });

  const { subscription } = await loadCaptainSubscriptionContext(captainUserId);
  queueNotification({
    userId: Number(captainUserId),
    type: "taxi.captain.subscription.discount_updated",
    title: "تم تحديث خصم الاشتراك",
    body: `نسبة الخصم الحالية ${subscription.discountPercent}%`,
    payload: {
      discountPercent: subscription.discountPercent,
      monthlyFeeIqd: subscription.monthlyFeeIqd,
      discountedMonthlyFeeIqd: subscription.discountedMonthlyFeeIqd,
    },
  });

  return {
    captainUserId: Number(captainUserId),
    subscription,
  };
}

export async function confirmCaptainCashPaymentByAdmin({
  captainUserId,
  adminUserId,
  cycleDays = 30,
}) {
  const captain = await repo.getCaptainProfile(captainUserId);
  if (!captain) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }

  const now = new Date();
  const safeCycleDays = Math.max(1, Math.min(365, Number(cycleDays) || 30));
  const cycleEndAt = addDays(now, safeCycleDays);

  const updated = await repo.confirmCaptainCashPayment({
    captainUserId,
    cycleStartAt: now.toISOString(),
    cycleEndAt: cycleEndAt.toISOString(),
    approvedByUserId: adminUserId,
  });

  if (!updated) {
    throw new AppError("TAXI_CAPTAIN_SUBSCRIPTION_NOT_FOUND", { status: 404 });
  }

  const { subscription } = await loadCaptainSubscriptionContext(captainUserId);
  queueNotification({
    userId: Number(captainUserId),
    type: "taxi.captain.subscription.cash_payment_confirmed",
    title: "تم تأكيد تسديد الاشتراك",
    body: `تم تفعيل اشتراكك لمدة ${safeCycleDays} يوم.`,
    payload: {
      cycleStartAt: updated.current_cycle_start_at,
      cycleEndAt: updated.current_cycle_end_at,
      remainingDays: subscription.remainingDays,
    },
  });

  return {
    captainUserId: Number(captainUserId),
    subscription,
  };
}

export async function listPendingCaptainCashPayments({ limit = 100 } = {}) {
  const rows = await repo.listPendingCaptainCashPayments({ limit });
  return rows.map((row) => {
    const subscription = evaluateCaptainSubscription(row);
    return {
      captainUserId: Number(row.captain_user_id),
      fullName: row.full_name || null,
      phone: row.phone || null,
      block: row.block || null,
      buildingNumber: row.building_number || null,
      apartment: row.apartment || null,
      profileImageUrl: row.profile_image_url || null,
      carImageUrl: row.car_image_url || null,
      carMake: row.car_make || null,
      carModel: row.car_model || null,
      carYear: row.car_year == null ? null : Number(row.car_year),
      plateNumber: row.plate_number || null,
      cashPaymentRequestedAt: row.cash_payment_requested_at || null,
      subscription,
    };
  });
}
