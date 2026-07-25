import { createNotification } from "../notifications/notifications.repo.js";
import { emitRealtimeToUser } from "../../shared/realtime/realtime-gateway.js";
import { AppError } from "../../shared/utils/errors.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { hashPin } from "../../shared/utils/hash.js";
import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import * as deliveryRepo from "../delivery/delivery.repo.js";
import * as repo from "./taxi.repo.js";
import * as loyaltyRepo from "./taxi.loyalty.repo.js";

const FIRST_SEARCH_RADIUS_M = 15000;
const EXPANDED_SEARCH_RADIUS_M = 15000;
const PRICE_RAISE_REJECTION_THRESHOLD = 5;
const SEARCH_STAGE_MINUTES = 5;
const NEGOTIATION_TIMEOUT_SECONDS = 90;
const CALL_RING_TIMEOUT_SECONDS = 35;
const CAPTAIN_SUBSCRIPTION_MONTHLY_FEE_IQD = 10000;

let lifecycleWorker = null;
let lifecycleRunning = false;
let lastLifecycleSweepAt = 0;
const LIFECYCLE_MIN_INTERVAL_MS = 4000;

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function assertValidBasmayaAddress(address) {
  const validation = validateBasmayaAddress(address);
  if (!validation.ok) {
    const err = new Error("INVALID_BASMAYA_ADDRESS");
    err.status = 400;
    err.fields = validation.errors;
    throw err;
  }
  return validation.normalized;
}

export async function registerCaptain(dto) {
  const address = assertValidBasmayaAddress({
    block: dto.block,
    buildingNumber: dto.buildingNumber,
    apartment: dto.apartment,
  });
  if (!normalizeConsentAccepted(dto.analyticsConsentAccepted)) {
    const err = new Error("ANALYTICS_CONSENT_REQUIRED");
    err.status = 400;
    throw err;
  }

  const phone = String(dto.phone || "").trim();
  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const fullName = String(dto.fullName || "").trim();
  const pinHash = await hashPin(dto.pin);
  const analyticsConsentVersion =
    typeof dto.analyticsConsentVersion === "string" &&
    dto.analyticsConsentVersion.trim().length > 0
      ? dto.analyticsConsentVersion.trim().slice(0, 32)
      : "taxi_registration_contract_v1";

  let user = null;
  try {
    user = await runWithGeneratedAppUserUsername({
      fullName,
      phone,
      execute: (username) =>
        createUser({
          fullName,
          username,
          phone,
          pinHash,
          block: address.block,
          buildingNumber: address.buildingNumber,
          apartment: address.apartment,
          imageUrl: dto.profileImageUrl || dto.imageUrl || null,
          role: "taxi_captain",
          analyticsConsentGranted: true,
          analyticsConsentVersion,
          analyticsConsentGrantedAt: new Date(),
          chatQualityReviewConsent: true,
        }),
    });

    await repo.setTaxiAccountPendingApproval(Number(user.id));
    await repo.createPendingCaptainProfile({
      userId: Number(user.id),
      profileImageUrl: dto.profileImageUrl || dto.imageUrl || null,
      carImageUrl: dto.carImageUrl || null,
      vehicleType: dto.vehicleType,
      carMake: dto.carMake,
      carModel: dto.carModel,
      carYear: dto.carYear,
      carColor: dto.carColor,
      plateNumber: dto.plateNumber,
      plateGovernorate: dto.plateGovernorate,
      plateCategory: dto.plateCategory,
      plateLetter: dto.plateLetter,
      plateDigits: dto.plateDigits,
    });
  } catch (error) {
    if (user?.id) {
      await deliveryRepo.deleteUserById(Number(user.id)).catch(() => {});
    }
    throw error;
  }

  const approvers = await deliveryRepo.listDeliveryApproverUserIds();
  await createManyNotifications(
    approvers.map((approverId) => ({
      userId: Number(approverId),
      type: "admin_taxi_captain_pending_approval",
      title: "Taxi captain account pending approval",
      body: `New taxi captain request: ${fullName} (${phone})`,
      payload: {
        captainUserId: Number(user.id),
      },
    }))
  );

  return {
    pendingApproval: true,
    message: "TAXI_CAPTAIN_ACCOUNT_PENDING_APPROVAL",
    user: {
      id: Number(user.id),
      fullName: user.full_name,
      phone: user.phone,
      role: user.role,
      isTaxiCaptain: true,
      taxiAccountApproved: false,
    },
  };
}

const IRAQ_PLATE_GOVERNORATES = [
  "بغداد",
  "البصرة",
  "نينوى",
  "أربيل",
  "السليمانية",
  "دهوك",
  "كركوك",
  "ديالى",
  "الأنبار",
  "بابل",
  "كربلاء",
  "النجف",
  "واسط",
  "القادسية",
  "المثنى",
  "ذي قار",
  "ميسان",
  "صلاح الدين",
];

const IRAQ_PLATE_CATEGORIES = [
  "خصوصي",
  "أجرة",
  "حمل",
  "حكومي",
  "زراعي",
  "إنشائية",
  "فحص مؤقت",
];

function normalizeCatalogLabel(value, max = 120) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, max);
}

export async function listVehicleCatalog() {
  const currentYear = new Date().getFullYear() + 1;
  const years = [];
  for (let year = currentYear; year >= 1990; year -= 1) years.push(year);
  const makes = await repo.listVehicleCatalog();
  return {
    makes,
    years,
    plateGovernorates: IRAQ_PLATE_GOVERNORATES,
    plateCategories: IRAQ_PLATE_CATEGORIES,
  };
}

export async function createVehicleMake({ name, userId = null }) {
  const label = normalizeCatalogLabel(name);
  if (label.length < 2) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["name"] },
    });
  }
  const make = await repo.createVehicleMake({ name: label, userId });
  return { make };
}

export async function createVehicleModel({ makeId, makeName = null, name, userId = null }) {
  const label = normalizeCatalogLabel(name);
  if (label.length < 1) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["name"] },
    });
  }
  const model = await repo.createVehicleModel({
    makeId,
    makeName: normalizeCatalogLabel(makeName),
    name: label,
    userId,
  });
  if (!model) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["makeId"] },
    });
  }
  return { model };
}

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
  const normalized = String(role || "").trim().toLowerCase();
  return normalized === "taxi_captain";
}

function hasCaptainTaxiProfileCompleteness(row) {
  if (!row) return false;
  const requiredFields = [
    row.full_name,
    row.phone,
    row.vehicle_type,
    row.car_model,
    row.car_color,
    row.plate_number,
  ];
  return requiredFields.every(
    (value) => String(value ?? "").trim().length > 0
  );
}

function buildCaptainTaxiEligibility({ profileRow, presenceRow }) {
  const profile = mapCaptainProfile(profileRow);
  const isOnline =
    presenceRow?.isOnline === true &&
    presenceRow?.latitude != null &&
    presenceRow?.longitude != null &&
    presenceRow?.lastSeenAt != null &&
    Date.now() - new Date(presenceRow.lastSeenAt).getTime() <= 3 * 60 * 1000;
  const isApproved = profile?.taxiAccountApproved === true;
  const isActive = profile?.isActive === true;
  const isProfileComplete = hasCaptainTaxiProfileCompleteness(profileRow);
  const canReceiveRideRequests =
    isApproved && isActive && isOnline && isProfileComplete;

  const reasons = [];
  if (!isApproved) reasons.push("not_approved");
  if (!isActive) reasons.push("inactive_profile");
  if (!isOnline) reasons.push("offline");
  if (!isProfileComplete) reasons.push("profile_incomplete");

  return {
    profile,
    presence: presenceRow || null,
    isApproved,
    isActive,
    isOnline,
    isProfileComplete,
    canReceiveRideRequests,
    reasons,
  };
}

async function loadCaptainTaxiEligibility(captainUserId) {
  const profileRow = await repo.getCaptainProfile(captainUserId);
  if (!profileRow) {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }
  const presenceRow = await repo.getCaptainPresence(captainUserId);
  return buildCaptainTaxiEligibility({ profileRow, presenceRow });
}

async function loadCaptainTaxiActionability(captainUserId) {
  const eligibility = await loadCaptainTaxiEligibility(captainUserId);
  const activeRide = await repo.getCaptainCurrentRide(captainUserId);
  const reasons = [...eligibility.reasons];
  if (activeRide) reasons.push("active_ride");

  return {
    ...eligibility,
    activeRide,
    reasons,
    canReceiveRideRequests: eligibility.canReceiveRideRequests && !activeRide,
  };
}

async function assertCaptainCanReceiveRideRequests(captainUserId) {
  const readiness = await loadCaptainTaxiActionability(captainUserId);
  if (readiness.canReceiveRideRequests) {
    return readiness;
  }

  throw new AppError("TAXI_CAPTAIN_NOT_AVAILABLE", {
    status: 403,
    details: {
      reasons: readiness.reasons,
      activeRideId: readiness.activeRide?.id || null,
    },
  });
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

async function ensureRideChatAccess({ ride, userId, role, isSuperAdmin }) {
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  if (!ride.assignedCaptainUserId) {
    throw new AppError("TAXI_RIDE_FORBIDDEN", { status: 403 });
  }

  if (isSuperAdmin === true || role === "admin" || role === "deputy_admin") {
    return { senderRole: "system" };
  }

  if (role === "user" && ride.customerUserId === Number(userId)) {
    return { senderRole: "customer" };
  }

  if (isCaptainRole(role)) {
    if (ride.assignedCaptainUserId === Number(userId)) {
      return { senderRole: "captain" };
    }
  }

  throw new AppError("TAXI_RIDE_FORBIDDEN", { status: 403 });
}

function buildCompactRidePayload(ride) {
  return {
    id: ride.id,
    status: ride.status,
    displayState: ride.displayState ?? null,
    isActiveRide: ride.isActiveRide === true,
    isSearchingRide: ride.isSearchingRide === true,
    isNegotiatingRide: ride.isNegotiatingRide === true,
    isTerminalRide: ride.isTerminalRide === true,
    proposedFareIqd: ride.proposedFareIqd,
    agreedFareIqd: ride.agreedFareIqd,
    currentBidId: ride.currentBidId,
    pickup: ride.pickup,
    dropoff: ride.dropoff,
    customerUserId: ride.customerUserId,
    assignedCaptainUserId: ride.assignedCaptainUserId,
    searchPhase: ride.searchPhase,
    searchRadiusM: ride.searchRadiusM,
    rejectedCaptainsCount: ride.rejectedCaptainsCount ?? 0,
    pricingRound: ride.pricingRound ?? 1,
    previousProposedFareIqd: ride.previousProposedFareIqd ?? null,
    priceRaiseRequiredAt: ride.priceRaiseRequiredAt ?? null,
    fareVersion: ride.fareVersion ?? 1,
    priceRaiseRequired: ride.priceRaiseRequired === true,
    priceRaiseRecommended: ride.priceRaiseRecommended === true,
    priceRaisePromptedAt: ride.priceRaisePromptedAt ?? null,
    finalAcceptanceDeadlineAt: ride.finalAcceptanceDeadlineAt ?? null,
    captainRating: ride.captainRating ?? null,
    captainReview: ride.captainReview ?? null,
    captainRatedAt: ride.captainRatedAt ?? null,
    createdAt: ride.createdAt,
    updatedAt: ride.updatedAt,
    isPriceRaiseRequiredRide: ride.isPriceRaiseRequiredRide === true,
  };
}

function toSafeNumber(value) {
  if (value == null) return null;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === "bigint") {
    return Number(value);
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toSafeInt(value) {
  const parsed = toSafeNumber(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function normalizeTaxiLabel(value) {
  const text = value == null ? "" : String(value).trim();
  return text.length > 0 ? text : null;
}

function haversineDistanceMeters(lat1, lng1, lat2, lng2) {
  const values = [lat1, lng1, lat2, lng2].map((value) => Number(value));
  if (values.some((value) => !Number.isFinite(value))) return null;

  const [aLat, aLng, bLat, bLng] = values.map((value) => (value * Math.PI) / 180);
  const deltaLat = bLat - aLat;
  const deltaLng = bLng - aLng;
  const sinLat = Math.sin(deltaLat / 2);
  const sinLng = Math.sin(deltaLng / 2);
  const a =
    sinLat * sinLat +
    Math.cos(aLat) * Math.cos(bLat) * sinLng * sinLng;
  return Math.round(2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(a))));
}

function minutesFromDistance(distanceM, speedKmh = 35) {
  const distance = toSafeNumber(distanceM);
  if (distance == null || distance <= 0) return null;
  const speed = Math.max(1, Number(speedKmh) || 35);
  return Math.max(1, Math.ceil((distance / 1000 / speed) * 60));
}

function buildTaxiAssignmentPayload(ride, { latestLocation = null } = {}) {
  if (!ride) return null;

  const pickup = ride.pickup || null;
  const dropoff = ride.dropoff || null;
  const captain = ride.captain || null;
  const latest = latestLocation && typeof latestLocation === "object"
    ? latestLocation
    : null;

  const pickupLatitude = toSafeNumber(pickup?.latitude);
  const pickupLongitude = toSafeNumber(pickup?.longitude);
  const destinationLatitude = toSafeNumber(dropoff?.latitude);
  const destinationLongitude = toSafeNumber(dropoff?.longitude);

  const captainLatitude = toSafeNumber(latest?.latitude);
  const captainLongitude = toSafeNumber(latest?.longitude);
  const captainHeading = toSafeNumber(latest?.headingDeg ?? latest?.heading_deg);
  const captainDistanceMeters =
    pickupLatitude != null &&
    pickupLongitude != null &&
    captainLatitude != null &&
    captainLongitude != null
      ? haversineDistanceMeters(
          pickupLatitude,
          pickupLongitude,
          captainLatitude,
          captainLongitude
        )
      : null;

  const routeDistance =
    toSafeNumber(ride.routeDistanceMeters) ??
    toSafeNumber(ride.routeDistance) ??
    (pickupLatitude != null &&
    pickupLongitude != null &&
    destinationLatitude != null &&
    destinationLongitude != null
      ? haversineDistanceMeters(
          pickupLatitude,
          pickupLongitude,
          destinationLatitude,
          destinationLongitude
        )
      : null);
  const routeDuration =
    toSafeNumber(ride.routeDurationSeconds) ??
    toSafeNumber(ride.routeDuration) ??
    (routeDistance != null ? Math.round((routeDistance / 1000 / 35) * 3600) : null);
  const estimatedArrivalMinutes =
    minutesFromDistance(captainDistanceMeters, 30) ??
    toSafeInt(ride.estimatedArrivalMinutes) ??
    minutesFromDistance(routeDistance, 35);

  const customerFare = toSafeInt(ride.proposedFareIqd ?? ride.customerFare);
  const finalFare = toSafeInt(
    ride.agreedFareIqd ?? ride.finalFare ?? ride.proposedFareIqd ?? ride.customerFare
  );
  const acceptedAt = ride.acceptedAt || ride.assignedAt || null;
  const assignedCaptainUserId =
    toSafeInt(ride.assignedCaptainUserId ?? ride.assigned_captain_user_id) ?? null;

  const captainCompletedTrips = toSafeInt(captain?.ridesCount) ?? null;
  const captainRating = toSafeNumber(captain?.ratingAvg);
  const captainRatingCount = toSafeInt(
    captain?.ratingCount ?? captain?.ridesCount
  );

  const captainSnapshot = captain
    ? {
        captainId:
          toSafeInt(captain.id ?? assignedCaptainUserId ?? ride.captainId) ??
          assignedCaptainUserId,
        captainName:
          normalizeTaxiLabel(captain.fullName) ||
          normalizeTaxiLabel(captain.name) ||
          null,
        captainPhoto:
          normalizeTaxiLabel(
            captain.profileImageUrl ?? captain.imageUrl ?? captain.photoUrl
          ) || null,
        captainRating,
        captainRatingCount,
        captainCompletedTrips,
        captainPhone: normalizeTaxiLabel(captain.phone) || null,
        captainLatitude,
        captainLongitude,
        captainHeading,
        captainDistanceMeters,
        captainEstimatedArrivalMinutes: estimatedArrivalMinutes,
      }
    : null;

  const vehicle = {
    vehicleId: toSafeInt(captain?.vehicleId ?? ride.vehicleId),
    vehicleMake: normalizeTaxiLabel(captain?.carMake ?? ride.vehicleMake) || null,
    vehicleModel:
      normalizeTaxiLabel(captain?.carModel ?? ride.vehicleModel) || null,
    vehicleYear:
      toSafeInt(captain?.carYear ?? ride.vehicleYear ?? ride.vehicleModelYear) ||
      null,
    vehicleColor: normalizeTaxiLabel(captain?.carColor ?? ride.vehicleColor) || null,
    vehicleType: normalizeTaxiLabel(captain?.vehicleType ?? ride.vehicleType) || null,
    vehiclePlate:
      normalizeTaxiLabel(captain?.plateNumber ?? ride.vehiclePlate) || null,
    vehiclePlateGovernorate:
      normalizeTaxiLabel(captain?.plateGovernorate ?? ride.vehiclePlateGovernorate) ||
      null,
    vehiclePlateCategory:
      normalizeTaxiLabel(captain?.plateCategory ?? ride.vehiclePlateCategory) ||
      null,
    vehiclePlateLetter:
      normalizeTaxiLabel(captain?.plateLetter ?? ride.vehiclePlateLetter) || null,
    vehiclePlateDigits:
      normalizeTaxiLabel(captain?.plateDigits ?? ride.vehiclePlateDigits) || null,
    vehicleNumber:
      normalizeTaxiLabel(
        captain?.plateDigits ??
          captain?.plateNumber ??
          ride.vehicleNumber ??
          captain?.vehicleNumber ??
          ride.vehiclePlate
      ) || null,
    vehicleImage:
      normalizeTaxiLabel(captain?.carImageUrl ?? ride.vehicleImage) || null,
  };

  return {
    rideId: toSafeInt(ride.id ?? ride.rideId),
    status: normalizeTaxiLabel(ride.status) || null,
    customerFare,
    finalFare,
    currency: normalizeTaxiLabel(ride.currency) || "IQD",
    pickupAddress: normalizeTaxiLabel(pickup?.label ?? ride.pickupAddress) || null,
    pickupLatitude,
    pickupLongitude,
    destinationAddress:
      normalizeTaxiLabel(dropoff?.label ?? ride.destinationAddress) || null,
    destinationLatitude,
    destinationLongitude,
    routeDistance,
    routeDuration,
    estimatedArrivalMinutes,
    assignedAt: acceptedAt,
    updatedAt: ride.updatedAt || null,
    captain: captainSnapshot,
    vehicle,
  };
}

function buildTaxiRideCompatView(ride, { latestLocation = null } = {}) {
  const assignment = buildTaxiAssignmentPayload(ride, { latestLocation });
  if (!assignment) return null;

  const captain = assignment.captain;
  const vehicle = assignment.vehicle;

  return {
    ...ride,
    id: assignment.rideId,
    rideId: assignment.rideId,
    status: assignment.status,
    customerFare: assignment.customerFare,
    finalFare: assignment.finalFare,
    currency: assignment.currency,
    pickupAddress: assignment.pickupAddress,
    pickupLatitude: assignment.pickupLatitude,
    pickupLongitude: assignment.pickupLongitude,
    destinationAddress: assignment.destinationAddress,
    destinationLatitude: assignment.destinationLatitude,
    destinationLongitude: assignment.destinationLongitude,
    routeDistance: assignment.routeDistance,
    routeDistanceMeters: assignment.routeDistance,
    routeDuration: assignment.routeDuration,
    routeDurationSeconds: assignment.routeDuration,
    estimatedArrivalMinutes: assignment.estimatedArrivalMinutes,
    assignedAt: assignment.assignedAt,
    acceptedAt: assignment.assignedAt,
    updatedAt: assignment.updatedAt,
    agreedFareIqd: assignment.finalFare ?? ride.agreedFareIqd ?? null,
    proposedFareIqd: assignment.customerFare ?? ride.proposedFareIqd ?? null,
    captain: captain
      ? {
          ...captain,
          id: captain.captainId,
          fullName: captain.captainName,
          profileImageUrl: captain.captainPhoto,
          phone: captain.captainPhone,
          ratingAvg: captain.captainRating,
          ratingCount: captain.captainRatingCount,
          ridesCount: captain.captainCompletedTrips,
          carMake: vehicle.vehicleMake,
          carModel: vehicle.vehicleModel,
          carYear: vehicle.vehicleYear,
          carColor: vehicle.vehicleColor,
          vehicleType: vehicle.vehicleType,
          plateNumber: vehicle.vehiclePlate,
          plateGovernorate: vehicle.vehiclePlateGovernorate,
          plateCategory: vehicle.vehiclePlateCategory,
          plateLetter: vehicle.vehiclePlateLetter,
          plateDigits: vehicle.vehiclePlateDigits,
          carImageUrl: vehicle.vehicleImage,
          vehicle: {
            ...vehicle,
            id: vehicle.vehicleId,
            make: vehicle.vehicleMake,
            model: vehicle.vehicleModel,
            year: vehicle.vehicleYear,
            color: vehicle.vehicleColor,
            type: vehicle.vehicleType,
            plate: vehicle.vehiclePlate,
            plateGovernorate: vehicle.vehiclePlateGovernorate,
            plateCategory: vehicle.vehiclePlateCategory,
            plateLetter: vehicle.vehiclePlateLetter,
            plateDigits: vehicle.vehiclePlateDigits,
            number: vehicle.vehicleNumber,
            imageUrl: vehicle.vehicleImage,
          },
        }
      : null,
    vehicle: vehicle.vehicleId != null || vehicle.vehicleMake != null
      ? {
          ...vehicle,
          id: vehicle.vehicleId,
          make: vehicle.vehicleMake,
          model: vehicle.vehicleModel,
          year: vehicle.vehicleYear,
          color: vehicle.vehicleColor,
          type: vehicle.vehicleType,
          plate: vehicle.vehiclePlate,
          plateGovernorate: vehicle.vehiclePlateGovernorate,
          plateCategory: vehicle.vehiclePlateCategory,
          plateLetter: vehicle.vehiclePlateLetter,
          plateDigits: vehicle.vehiclePlateDigits,
          number: vehicle.vehicleNumber,
          imageUrl: vehicle.vehicleImage,
        }
      : null,
    assignment,
  };
}

function buildTaxiOfferPayload(offer, { queuePosition = null } = {}) {
  if (!offer) return null;

  return {
    ...offer,
    offerId: offer.offerId ?? offer.id ?? null,
    bidId: offer.bidId ?? offer.id ?? null,
    captainId: offer.captainId ?? offer.captainUserId ?? null,
    captainUserId: offer.captainUserId ?? offer.captainId ?? null,
    distanceM: offer.distanceM ?? null,
    queuePosition: queuePosition ?? offer.queuePosition ?? null,
    isCurrent: offer.isCurrent === true,
    isBestPrice: offer.isBestPrice === true,
    isNearest: offer.isNearest === true,
    isHighestRated: offer.isHighestRated === true,
  };
}

export const __taxiServiceTestApi = {
  buildCompactRidePayload,
  buildTaxiAssignmentPayload,
  buildTaxiRideCompatView,
  buildBidQueueMeta,
  buildOfferPresentationList,
  buildTaxiOfferPayload,
  buildCaptainTaxiEligibility,
  hasCaptainTaxiProfileCompleteness,
  ensureRideChatAccess,
  shouldRecommendRidePriceRaise,
};

function shouldRecommendRidePriceRaise(ride) {
  if (!ride) return false;
  const rejectedCaptainsCount = Number(ride.rejectedCaptainsCount || 0);
  const deadlineMs = ride.finalAcceptanceDeadlineAt
    ? new Date(ride.finalAcceptanceDeadlineAt).getTime()
    : null;
  const deadlineExpired = deadlineMs != null && deadlineMs <= Date.now();
  return (
    String(ride.status || "").trim().toLowerCase() === "price_raise_required" ||
    rejectedCaptainsCount >= PRICE_RAISE_REJECTION_THRESHOLD ||
    deadlineExpired
  );
}

async function maybePromptRidePriceRaise(ride) {
  if (!ride) return { recommended: false, prompted: false };

  const recommended = shouldRecommendRidePriceRaise(ride);
  ride.priceRaiseRecommended = recommended;
  if (!recommended) return { recommended: false, prompted: false };

  if (ride.priceRaisePromptedAt) {
    return { recommended: true, prompted: false };
  }

  const mark = await repo.markRidePriceRaisePrompted(ride.id);
  if (!mark.updated) {
    return { recommended: true, prompted: false };
  }

  ride.priceRaisePromptedAt = new Date().toISOString();
  try {
    await createNotification({
      userId: ride.customerUserId,
      type: "taxi.ride.price_raise_recommended",
      title: "ننصح برفع السعر",
      body: "تم رفض الطلب عدة مرات أو انتهت مهلة القبول. رفع السعر يزيد فرص القبول.",
      payload: {
        rideId: ride.id,
        rejectedCaptainsCount: Number(ride.rejectedCaptainsCount || 0),
        finalAcceptanceDeadlineAt: ride.finalAcceptanceDeadlineAt || null,
      },
    });
  } catch (error) {
    console.warn(
      "[taxi] price raise notification queue failed",
      error?.message || error
    );
  }

  void emitRealtimeToUser(ride.customerUserId, "taxi_ride_update", {
    eventType: "price_raise_recommended",
    ride: buildCompactRidePayload(ride),
    rejectedCaptainsCount: Number(ride.rejectedCaptainsCount || 0),
  });

  return { recommended: true, prompted: true };
}

function sortBidQueueByCreatedAt(bids) {
  return [...bids].sort((a, b) => {
    const ta = new Date(a.createdAt || 0).getTime();
    const tb = new Date(b.createdAt || 0).getTime();
    if (ta !== tb) return ta - tb;
    return Number(a.id || 0) - Number(b.id || 0);
  });
}

function buildNegotiationWindowMeta(bid, nowMs = Date.now()) {
  const anchorAt = new Date(bid?.updatedAt || bid?.createdAt || Date.now());
  const expiresAtMs =
    anchorAt.getTime() + NEGOTIATION_TIMEOUT_SECONDS * 1000;
  const remainingSeconds = Math.max(
    0,
    Math.ceil((expiresAtMs - nowMs) / 1000)
  );

  return {
    startedAt: anchorAt.toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString(),
    remainingSeconds,
    timeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
    isExpired: remainingSeconds <= 0,
  };
}

function buildBidQueueMeta({ bids, currentBidId }) {
  const nowMs = Date.now();
  const activeQueue = sortBidQueueByCreatedAt(
    bids.filter((b) => b.status === "active")
  );
  const currentBid = activeQueue.find(
    (entry) => Number(entry.id) === Number(currentBidId)
  );
  const bestFare = activeQueue
    .map((bid) => Number(bid.offeredFareIqd || 0))
    .filter((fare) => fare > 0)
    .reduce((min, fare) => Math.min(min, fare), Number.POSITIVE_INFINITY);
  const nearestDistance = activeQueue
    .map((bid) => Number(bid.distanceM || 0))
    .filter((distance) => distance > 0)
    .reduce((min, distance) => Math.min(min, distance), Number.POSITIVE_INFINITY);
  const highestRating = activeQueue
    .map((bid) => Number(bid.captain?.ratingAvg || 0))
    .filter((rating) => rating > 0)
    .reduce((max, rating) => Math.max(max, rating), 0);

  const currentNegotiation = currentBid
    ? buildNegotiationWindowMeta(currentBid, nowMs)
    : null;
  const queue = activeQueue.map((b, index) => {
    const distanceM = b.distanceM == null ? null : Number(b.distanceM);
    const captainRating = Number(b.captain?.ratingAvg || 0);
    return {
      bidId: b.id,
      offerId: b.id,
      captainId: b.captainUserId,
      captainUserId: b.captainUserId,
      offeredFareIqd: b.offeredFareIqd,
      etaMinutes: b.etaMinutes ?? null,
      queuePosition: index + 1,
      isCurrent: Number(currentBidId) === Number(b.id),
      counterOfferCount: Number(b.counterOfferCount || 0),
      lastOfferIqd: b.lastOfferIqd ?? b.offeredFareIqd,
      lastOfferBy: b.lastOfferBy || "captain",
      createdAt: b.createdAt,
      updatedAt: b.updatedAt,
      distanceM,
      captainRatingAvg: captainRating || null,
      isBestPrice:
        Number.isFinite(bestFare) &&
        bestFare !== Number.POSITIVE_INFINITY &&
        Number(b.offeredFareIqd || 0) === bestFare,
      isNearest:
        Number.isFinite(nearestDistance) &&
        nearestDistance !== Number.POSITIVE_INFINITY &&
        distanceM != null &&
        distanceM === nearestDistance,
      isHighestRated:
        highestRating > 0 &&
        captainRating > 0 &&
        captainRating === highestRating,
      negotiation: buildNegotiationWindowMeta(b, nowMs),
    };
  });
  return {
    currentBidId: currentBidId || null,
    currentOfferId: currentBidId || null,
    queueSize: activeQueue.length,
    offerCount: activeQueue.length,
    generatedAt: new Date(nowMs).toISOString(),
    negotiationTimeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
    currentNegotiation,
    queue,
    offerQueue: queue,
    offers: queue,
    currentOffer: queue.find((entry) => entry.isCurrent) || null,
  };
}

function buildOfferPresentationList({ bids, currentBidId, bidQueue = null }) {
  const queueIndex = new Map(
    (bidQueue?.queue || []).map((entry) => [Number(entry.bidId), entry])
  );

  return sortBidQueueByCreatedAt(
    bids.filter((bid) => bid.status === "active")
  ).map((bid) => {
    const queueMeta = queueIndex.get(Number(bid.id)) || null;
    return buildTaxiOfferPayload(
      {
        ...bid,
        offerId: bid.id,
        captainId: bid.captainUserId,
        queuePosition: queueMeta?.queuePosition ?? null,
        isCurrent:
          queueMeta?.isCurrent === true ||
          Number(currentBidId) === Number(bid.id),
        isBestPrice: queueMeta?.isBestPrice === true,
        isNearest: queueMeta?.isNearest === true,
        isHighestRated: queueMeta?.isHighestRated === true,
        distanceM: bid.distanceM ?? queueMeta?.distanceM ?? null,
      },
      { queuePosition: queueMeta?.queuePosition ?? null }
    );
  });
}

async function resolveNegotiationCaptainUserId(ride) {
  if (!ride) return null;
  if (ride.assignedCaptainUserId) return Number(ride.assignedCaptainUserId);
  if (!ride.currentBidId) return null;
  const currentBid = await repo.getRideCurrentBid(ride.id);
  if (!currentBid) return null;
  return Number(currentBid.captainUserId);
}

function buildCallSessionPayload(session) {
  if (!session) return null;
  return {
    id: session.id,
    rideRequestId: session.rideRequestId,
    initiatorUserId: session.initiatorUserId,
    receiverUserId: session.receiverUserId,
    status: session.status,
    startedAt: session.startedAt,
    answeredAt: session.answeredAt,
    endedAt: session.endedAt,
    endedByUserId: session.endedByUserId,
    endReason: session.endReason,
  };
}

async function ensureRideCallParticipant({ ride, userId, role, isSuperAdmin }) {
  const access = await ensureRideChatAccess({ ride, userId, role, isSuperAdmin });
  if (!["customer", "captain"].includes(access.senderRole)) {
    throw new AppError("TAXI_CALL_FORBIDDEN", { status: 403 });
  }
  return access.senderRole;
}

async function resolveRideCallPeerUserId({ ride, senderUserId, senderRole }) {
  if (senderRole === "customer") {
    const captainId =
      ride.assignedCaptainUserId || (await resolveNegotiationCaptainUserId(ride));
    if (!captainId) return null;
    if (Number(captainId) === Number(senderUserId)) return null;
    return Number(captainId);
  }
  if (senderRole === "captain") {
    if (Number(ride.customerUserId) === Number(senderUserId)) return null;
    return Number(ride.customerUserId);
  }
  return null;
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

function emitTaxiRealtimeEvents(userId, eventNames, payload) {
  const events = Array.isArray(eventNames) ? eventNames : [eventNames];
  for (const eventName of events) {
    if (!eventName) continue;
    void emitRealtimeToUser(userId, eventName, payload);
  }
}

async function emitRideUpdate(ride, eventType, extra = {}) {
  if (!ride) return;
  const latestLocation = extra.latestLocation || null;
  const rideView = buildTaxiRideCompatView(ride, { latestLocation });

  const payload = {
    eventType,
    ride: rideView,
    assignment: rideView?.assignment || buildTaxiAssignmentPayload(ride, { latestLocation }),
    ...extra,
  };

  void emitRealtimeToUser(ride.customerUserId, "taxi_ride_update", payload);
  if (ride.assignedCaptainUserId) {
    void emitRealtimeToUser(ride.assignedCaptainUserId, "taxi_ride_update", payload);
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
    emitTaxiRealtimeEvents(captain.captainUserId, [
      "taxi_ride_requested",
      "taxi_new_request",
    ], {
      ride: buildCompactRidePayload(ride),
      rideId: ride.id,
      pickupLabel: ride.pickup?.label || null,
      destinationLabel: ride.dropoff?.label || null,
      suggestedFareIqd: ride.proposedFareIqd,
      distanceM: captain.distanceM,
      customerUserId: ride.customerUserId,
    });
  }

  queueNotifications(
    nearbyCaptains.map((captain) => ({
      userId: captain.captainUserId,
      type: "taxi.ride.requested",
      title: "طلب تكسي قريب منك",
      body: `سعر مقترح ${ride.proposedFareIqd} د.ع`,
      payload: {
        rideId: ride.id,
        pickupLabel: ride.pickup?.label || null,
        destinationLabel: ride.dropoff?.label || null,
        suggestedFareIqd: ride.proposedFareIqd,
        searchRadiusM: ride.searchRadiusM,
        distanceM: captain.distanceM,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_requested",
        requiresAction: true,
      },
    }))
  );

  return nearbyCaptains.length;
}

async function processNegotiationTimeoutsAndEmit() {
  const staleCandidates = await repo.listRidesWithStaleCurrentBid({
    timeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
    limit: 140,
  });

  for (const stale of staleCandidates) {
    const timedOut = await repo.timeoutCurrentRideBidAndPromote({
      rideId: stale.rideId,
      expectedBidId: stale.currentBidId,
    });
    if (!timedOut || timedOut.code !== "OK" || !timedOut.ride) continue;

    const ride = timedOut.ride;
    const bids = await repo.listRideBids(ride.id);
    const bidQueue = buildBidQueueMeta({
      bids,
      currentBidId: ride.currentBidId,
    });
    const offers = buildOfferPresentationList({
      bids,
      currentBidId: ride.currentBidId,
      bidQueue,
    });
    const timedOutOffer =
      offers.find((entry) => Number(entry.offerId) === Number(timedOut.timedOutBid?.id)) ||
      buildTaxiOfferPayload(
        {
          ...timedOut.timedOutBid,
          offerId: timedOut.timedOutBid?.id || null,
          captainId: timedOut.timedOutBid?.captainUserId || null,
          status: "rejected",
        },
        {}
      );
    const nextOffer =
      timedOut.nextBid != null
        ? offers.find((entry) => Number(entry.offerId) === Number(timedOut.nextBid.id)) ||
          buildTaxiOfferPayload(
            {
              ...timedOut.nextBid,
              offerId: timedOut.nextBid.id,
              captainId: timedOut.nextBid.captainUserId,
            },
            {}
          )
        : null;

    await repo.createRideEvent({
      rideRequestId: ride.id,
      actorUserId: ride.customerUserId,
      eventType: timedOut.nextBid
        ? "offer_timeout_switched"
        : "offer_timeout_no_next",
      message: timedOut.nextBid
        ? "انتهت مهلة التفاوض للكابتن الحالي وتم التحويل تلقائيًا للكابتن التالي."
        : "انتهت مهلة التفاوض للكابتن الحالي ولا يوجد كابتن بديل الآن.",
      payload: {
        timedOutBidId: timedOut.timedOutBid?.id || null,
        timedOutOfferId: timedOut.timedOutBid?.id || null,
        nextBidId: timedOut.nextBid?.id || null,
        nextOfferId: timedOut.nextBid?.id || null,
        timeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
        customerUserId: ride.customerUserId,
      },
    });

    emitTaxiRealtimeEvents(ride.customerUserId, [
      "taxi_offer_rejected",
      "taxi_bid_update",
    ], {
      eventType: "offer_timeout_switched",
      rideId: ride.id,
      bidQueue,
      offers,
      timedOutBidId: timedOut.timedOutBid?.id || null,
      nextBidId: timedOut.nextBid?.id || null,
      timedOutOffer,
      nextOffer,
      customerUserId: ride.customerUserId,
    });

    if (timedOut.timedOutBid?.captainUserId) {
      emitTaxiRealtimeEvents(timedOut.timedOutBid.captainUserId, [
        "taxi_offer_rejected",
        "taxi_ride_unavailable",
        "taxi_bid_update",
      ], {
        eventType: "offer_timeout",
        rideId: ride.id,
        bidId: timedOut.timedOutBid.id,
        offerId: timedOut.timedOutBid.id,
        timedOutOffer,
        customerUserId: ride.customerUserId,
      });
      queueNotification({
        userId: timedOut.timedOutBid.captainUserId,
        type: "taxi.offer.timeout",
        title: "انتهت مهلة التفاوض",
        body: "انتهت المهلة وانتقل الطلب تلقائيًا للكابتن التالي.",
        payload: {
          rideId: ride.id,
          bidId: timedOut.timedOutBid.id,
          offerId: timedOut.timedOutBid.id,
          timeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
          captainId: timedOut.timedOutBid.captainUserId,
          customerUserId: ride.customerUserId,
          target: "taxi_ride_unavailable",
        },
      });
    }

    if (timedOut.nextBid?.captainUserId) {
      emitTaxiRealtimeEvents(timedOut.nextBid.captainUserId, [
        "taxi_offer_received",
        "taxi_bid_update",
      ], {
        eventType: "you_are_current_offer",
        rideId: ride.id,
        bidId: timedOut.nextBid.id,
        offerId: timedOut.nextBid.id,
        offer: nextOffer,
        bidQueue,
        offers,
        customerUserId: ride.customerUserId,
      });

      queueNotification({
        userId: timedOut.nextBid.captainUserId,
        type: "taxi.offer.received",
        title: "دورك الآن للتفاوض",
        body: `لديك ${NEGOTIATION_TIMEOUT_SECONDS} ثانية للرد قبل التحويل التلقائي.`,
        payload: {
          rideId: ride.id,
          bidId: timedOut.nextBid.id,
          offerId: timedOut.nextBid.id,
          timeoutSeconds: NEGOTIATION_TIMEOUT_SECONDS,
          captainId: timedOut.nextBid.captainUserId,
          customerUserId: ride.customerUserId,
          target: "taxi_offer_received",
        },
      });
    } else {
      queueNotification({
        userId: ride.customerUserId,
        type: "taxi.ride.unavailable",
        title: "لا يوجد عرض نشط الآن",
        body: "سنستمر في البحث عن كابتن قريب تلقائيًا.",
        payload: {
          rideId: ride.id,
          status: ride.status,
          customerUserId: ride.customerUserId,
          target: "taxi_ride_unavailable",
        },
      });
    }
  }
}

async function processRingingCallTimeoutsAndEmit() {
  const staleCalls = await repo.listStaleRingingCallSessions({
    timeoutSeconds: CALL_RING_TIMEOUT_SECONDS,
    limit: 120,
  });

  for (const call of staleCalls) {
    const ended = await repo.endRideCallSession({
      sessionId: call.id,
      endedByUserId: null,
      endReason: "timeout",
      status: "missed",
    });
    if (!ended) continue;

    const signal = await repo.insertRideCallSignal({
      callSessionId: ended.id,
      rideRequestId: ended.rideRequestId,
      senderUserId: ended.initiatorUserId,
      signalType: "decline",
      signalPayload: {
        reason: "timeout",
        status: "missed",
      },
    });

    const payload = {
      eventType: "call_missed",
      rideId: ended.rideRequestId,
      session: buildCallSessionPayload(ended),
      signal,
    };

    void emitRealtimeToUser(ended.initiatorUserId, "taxi_call_update", payload);
    void emitRealtimeToUser(ended.receiverUserId, "taxi_call_update", payload);

    queueNotification({
      userId: ended.initiatorUserId,
      type: "taxi.call.missed",
      title: "لم يتم الرد على المكالمة",
      body: "انتهت مهلة الرنين. يمكنك إعادة المحاولة.",
      payload: {
        rideId: ended.rideRequestId,
        callSessionId: ended.id,
      },
    });
  }
}

async function processSearchingLifecycleAndEmit({ force = false } = {}) {
  if (lifecycleRunning) return;
  if (
    force !== true &&
    lastLifecycleSweepAt > 0 &&
    Date.now() - lastLifecycleSweepAt < LIFECYCLE_MIN_INTERVAL_MS
  ) {
    return;
  }
  lifecycleRunning = true;
  lastLifecycleSweepAt = Date.now();

  try {
    await processRingingCallTimeoutsAndEmit();
    await processNegotiationTimeoutsAndEmit();

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
          message: "تم توسيع نطاق البحث عن كابتن إلى 15 كم.",
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
          body: "تم توسيع نطاق البحث إلى 15 كم لمدة 5 دقائق إضافية.",
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
    lastLifecycleSweepAt = Date.now();
  }
}

export function startTaxiLifecycleWorker({ intervalMs = 5000 } = {}) {
  if (lifecycleWorker) return;

  lifecycleWorker = setInterval(() => {
    processSearchingLifecycleAndEmit({ force: true }).catch((error) => {
      console.warn("[taxi] worker tick failed", error?.message || error);
    });
  }, Math.max(5000, Number(intervalMs) || 20000));

  lifecycleWorker.unref?.();
  void processSearchingLifecycleAndEmit({ force: true });
}

export async function createRideRequest(customerUserId, dto) {
  await processSearchingLifecycleAndEmit();

  const current = await repo.getCustomerCurrentRide(customerUserId);
  if (current) {
    throw new AppError("TAXI_ACTIVE_RIDE_EXISTS", { status: 409 });
  }

  let couponPreview = null;
  if (dto.couponCode) {
    const preview = await loyaltyRepo.getCouponPreviewForUser({
      userId: customerUserId,
      couponCode: dto.couponCode,
      proposedFareIqd: dto.proposedFareIqd,
    });
    if (preview.code !== "OK") {
      throw new AppError(preview.code, { status: 409 });
    }
    couponPreview = preview;
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
    searchRadiusM: Math.max(
      FIRST_SEARCH_RADIUS_M,
      Number(dto.searchRadiusM) || FIRST_SEARCH_RADIUS_M
    ),
    note: dto.note,
    scheduleMode: dto.scheduleMode,
    scheduledRideId: dto.scheduledRideId,
    scheduledFor: dto.scheduledFor,
    couponId: couponPreview?.coupon?.id ?? null,
    couponCodeSnapshot: couponPreview?.coupon?.code ?? dto.couponCode ?? null,
    couponUseIndex: couponPreview?.useIndex ?? null,
    fareBeforeDiscountIqd:
      couponPreview?.fareBeforeDiscountIqd ?? Number(dto.proposedFareIqd),
    couponDiscountIqd: couponPreview?.discountIqd ?? 0,
    fareAfterDiscountIqd:
      couponPreview?.fareAfterDiscountIqd ?? Number(dto.proposedFareIqd),
    couponSettlementState: couponPreview ? "reserved" : "none",
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
      scheduleMode: ride.scheduleMode,
      scheduledFor: ride.scheduledFor,
      couponCode: ride.couponCodeSnapshot,
      couponDiscountIqd: ride.couponDiscountIqd,
      fareBeforeDiscountIqd: ride.fareBeforeDiscountIqd,
      fareAfterDiscountIqd: ride.fareAfterDiscountIqd,
    },
  });

  const nearbyCaptainsCount = await notifyCaptainsNearRide(ride);

  return {
    ride: buildTaxiRideCompatView(ride),
    assignment: buildTaxiAssignmentPayload(ride),
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
    deliveryAccountApproved: row.taxi_account_approved === true,
    taxiAccountApproved: row.taxi_account_approved === true,
    profileImageUrl: row.profile_image_url || null,
    carImageUrl: row.car_image_url || null,
    vehicleType: row.vehicle_type || null,
    carMake: row.car_make || null,
    carModel: row.car_model || null,
    carYear: row.car_year == null ? null : Number(row.car_year),
    carColor: row.car_color || null,
    plateNumber: row.plate_number || null,
    plateGovernorate: row.plate_governorate || null,
    plateCategory: row.plate_category || null,
    plateLetter: row.plate_letter || null,
    plateDigits: row.plate_digits || null,
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
    "plateGovernorate",
    "plateCategory",
    "plateLetter",
    "plateDigits",
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

function mapCaptainProfileEditRequest(row) {
  const requestedChanges =
    row?.requested_changes && typeof row.requested_changes === "object"
      ? row.requested_changes
      : {};

  const currentProfile = {
    fullName: row?.full_name || null,
    phone: row?.phone || null,
    block: row?.block || null,
    buildingNumber: row?.building_number || null,
    apartment: row?.apartment || null,
    profileImageUrl: row?.profile_image_url || null,
    carImageUrl: row?.car_image_url || null,
    vehicleType: row?.vehicle_type || null,
    carMake: row?.car_make || null,
    carModel: row?.car_model || null,
    carYear: row?.car_year == null ? null : Number(row.car_year),
    carColor: row?.car_color || null,
    plateNumber: row?.plate_number || null,
    plateGovernorate: row?.plate_governorate || null,
    plateCategory: row?.plate_category || null,
    plateLetter: row?.plate_letter || null,
    plateDigits: row?.plate_digits || null,
  };

  return {
    id: Number(row?.id || 0),
    captainUserId: Number(row?.captain_user_id || 0),
    fullName: row?.full_name || null,
    phone: row?.phone || null,
    block: row?.block || null,
    buildingNumber: row?.building_number || null,
    apartment: row?.apartment || null,
    captainNote: row?.captain_note || null,
    requestedAt: row?.requested_at || null,
    reviewedAt: row?.reviewed_at || null,
    adminNote: row?.admin_note || null,
    status: String(row?.status || "pending").trim().toLowerCase(),
    requestedChanges,
    currentProfile,
  };
}

export async function listCustomerRideHistory(customerUserId, query = {}) {
  return repo.listCustomerRideHistoryByPeriod(customerUserId, query);
}

export async function rebookRideByCustomer({ customerUserId, rideId }) {
  await processSearchingLifecycleAndEmit();

  const current = await repo.getCustomerCurrentRide(customerUserId);
  if (current) {
    throw new AppError("TAXI_ACTIVE_RIDE_EXISTS", { status: 409 });
  }

  const sourceRide = await repo.getRideByIdForCustomer(rideId, customerUserId);
  if (!sourceRide) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }
  if (!["completed", "cancelled", "expired"].includes(String(sourceRide.status || ""))) {
    throw new AppError("TAXI_REBOOK_ONLY_CLOSED_RIDES", { status: 409 });
  }

  const result = await createRideRequest(customerUserId, {
    pickupLatitude: Number(sourceRide.pickup?.latitude),
    pickupLongitude: Number(sourceRide.pickup?.longitude),
    dropoffLatitude: Number(sourceRide.dropoff?.latitude),
    dropoffLongitude: Number(sourceRide.dropoff?.longitude),
    pickupLabel: String(sourceRide.pickup?.label || "").trim(),
    dropoffLabel: String(sourceRide.dropoff?.label || "").trim(),
    proposedFareIqd:
      Number(
        sourceRide.agreedFareIqd ||
          sourceRide.fareAfterDiscountIqd ||
          sourceRide.proposedFareIqd
      ) || 0,
    note: "rebook_from_previous_ride",
    couponCode: null,
    scheduleMode: "now",
    scheduledRideId: null,
    scheduledFor: null,
  });

  await repo.createRideEvent({
    rideRequestId: result.ride.id,
    actorUserId: customerUserId,
    eventType: "ride_rebooked",
    message: "تمت إعادة طلب المشوار من رحلة سابقة.",
    payload: {
      sourceRideId: Number(sourceRide.id),
      sourceRideStatus: sourceRide.status,
    },
  });

  return {
    ...result,
    sourceRideId: Number(sourceRide.id),
  };
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

  if (ride.status === "searching") {
    const ensured = await repo.ensureRideCurrentBid(ride.id);
    if (ensured && Number(ride.currentBidId || 0) !== Number(ensured.id)) {
      ride.currentBidId = ensured.id;
    }
  }
  await maybePromptRidePriceRaise(ride);

  const [bids, latestLocation, events, chatMessages, callState] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 60 }),
    repo.listRideChatMessages(ride.id, { limit: 80 }),
    repo.getRideCallState(ride.id, { signalLimit: 120 }),
  ]);

  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });

  return {
    ride: buildTaxiRideCompatView(ride, { latestLocation }),
    assignment: buildTaxiAssignmentPayload(ride, { latestLocation }),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    latestLocation,
    events: [...events].reverse(),
    chatMessages: [...chatMessages].reverse(),
    currentCallSession: callState.session,
  };
}

export async function getCurrentRideForCaptain(captainUserId) {
  await assertCaptainSubscriptionAccess(captainUserId);
  await processSearchingLifecycleAndEmit();

  const ride = await repo.getCaptainCurrentRide(captainUserId);
  if (!ride) return null;

  const [bids, latestLocation, events, chatMessages, callState] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 60 }),
    repo.listRideChatMessages(ride.id, { limit: 80 }),
    repo.getRideCallState(ride.id, { signalLimit: 120 }),
  ]);

  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });

  return {
    ride: buildTaxiRideCompatView(ride, { latestLocation }),
    assignment: buildTaxiAssignmentPayload(ride, { latestLocation }),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    latestLocation,
    events: [...events].reverse(),
    chatMessages: [...chatMessages].reverse(),
    currentCallSession: callState.session,
  };
}

export async function getRideDetails({ rideId, userId, role, isSuperAdmin }) {
  await processSearchingLifecycleAndEmit();

  const ride = await repo.getRideById(rideId);
  ensureRideAccess({ ride, userId, role, isSuperAdmin });

  const [bids, latestLocation, events, chatMessages, callState] = await Promise.all([
    repo.listRideBids(ride.id),
    repo.getLatestRideLocation(ride.id),
    repo.listRideEvents(ride.id, { limit: 120 }),
    repo.listRideChatMessages(ride.id, { limit: 120 }),
    repo.getRideCallState(ride.id, { signalLimit: 200 }),
  ]);

  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });

  return {
    ride: buildTaxiRideCompatView(ride, { latestLocation }),
    assignment: buildTaxiAssignmentPayload(ride, { latestLocation }),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    latestLocation,
    events: [...events].reverse(),
    chatMessages: [...chatMessages].reverse(),
    currentCallSession: callState.session,
  };
}

export async function listRideChatMessages({
  rideId,
  userId,
  role,
  isSuperAdmin,
  limit = 120,
}) {
  const ride = await repo.getRideById(rideId);
  await ensureRideChatAccess({ ride, userId, role, isSuperAdmin });

  const messages = await repo.listRideChatMessages(ride.id, { limit });
  return {
    ride,
    messages: [...messages].reverse(),
  };
}

export async function sendRideChatMessage({
  rideId,
  userId,
  role,
  isSuperAdmin,
  dto,
}) {
  const ride = await repo.getRideById(rideId);
  const access = await ensureRideChatAccess({ ride, userId, role, isSuperAdmin });
  const senderRole = access.senderRole;

  const text = String(dto.messageText || "").trim();
  if (!text) {
    throw new AppError("TAXI_CHAT_EMPTY_MESSAGE", { status: 400 });
  }

  const message = await repo.insertRideChatMessage({
    rideRequestId: ride.id,
    senderUserId: userId,
    senderRole,
    messageType: "text",
    messageText: text,
  });

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: userId,
    eventType: "chat_message_sent",
    message: "تم إرسال رسالة ضمن محادثة الرحلة.",
    payload: {
      messageId: message?.id || null,
      senderRole,
    },
  });

  const targetUsers = new Set([Number(ride.customerUserId)]);
  if (ride.assignedCaptainUserId) {
    targetUsers.add(Number(ride.assignedCaptainUserId));
  } else {
    const currentCaptainUserId = await resolveNegotiationCaptainUserId(ride);
    if (currentCaptainUserId) targetUsers.add(Number(currentCaptainUserId));
  }

  for (const targetUserId of targetUsers) {
    emitTaxiRealtimeEvents(targetUserId, [
      "taxi_chat_message",
      "taxi_chat_update",
    ], {
      eventType: "chat_message",
      rideId: ride.id,
      message,
    });
  }

  for (const targetUserId of targetUsers) {
    if (Number(targetUserId) === Number(userId)) continue;
    queueNotification({
      userId: Number(targetUserId),
      type: "taxi.chat.message",
      title: "رسالة جديدة في رحلة التكسي",
      body: text.length > 70 ? `${text.slice(0, 70)}...` : text,
      payload: {
        rideId: ride.id,
        messageId: message?.id || null,
        target: "taxi_chat_message",
      },
    });
  }

  return {
    rideId: ride.id,
    message,
  };
}

export async function getRideCallState({
  rideId,
  userId,
  role,
  isSuperAdmin,
  signalLimit = 160,
}) {
  const ride = await repo.getRideById(rideId);
  await ensureRideCallParticipant({ ride, userId, role, isSuperAdmin });

  const state = await repo.getRideCallState(ride.id, { signalLimit });
  return {
    rideId: ride.id,
    session: state.session,
    signals: [...(state.signals || [])].reverse(),
    selfUserId: Number(userId),
  };
}

export async function startRideCall({
  rideId,
  userId,
  role,
  isSuperAdmin,
}) {
  const ride = await repo.getRideById(rideId);
  const senderRole = await ensureRideCallParticipant({
    ride,
    userId,
    role,
    isSuperAdmin,
  });
  const peerUserId = await resolveRideCallPeerUserId({
    ride,
    senderUserId: userId,
    senderRole,
  });
  if (!peerUserId) {
    throw new AppError("TAXI_CALL_PEER_NOT_AVAILABLE", { status: 409 });
  }

  const active = await repo.getActiveRideCallSession(ride.id);
  if (
    active &&
    [active.initiatorUserId, active.receiverUserId].includes(Number(userId))
  ) {
    return {
      rideId: ride.id,
      session: buildCallSessionPayload(active),
      reused: true,
    };
  }

  if (active) {
    await repo.endActiveRideCallByRide({
      rideId: ride.id,
      endedByUserId: userId,
      endReason: "replaced",
      status: "ended",
    });
  }

  const session = await repo.createRideCallSession({
    rideRequestId: ride.id,
    initiatorUserId: userId,
    receiverUserId: peerUserId,
  });

  const signal = await repo.insertRideCallSignal({
    callSessionId: session.id,
    rideRequestId: ride.id,
    senderUserId: userId,
    signalType: "ringing",
    signalPayload: { senderRole },
  });

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: userId,
    eventType: "call_started",
    message: "بدأ اتصال بين الزبون والكابتن.",
    payload: {
      callSessionId: session.id,
      initiatorUserId: session.initiatorUserId,
      receiverUserId: session.receiverUserId,
    },
  });

  const payload = {
    eventType: "incoming_call",
    rideId: ride.id,
    session: buildCallSessionPayload(session),
    signal,
  };
  void emitRealtimeToUser(peerUserId, "taxi_call_update", payload);
  void emitRealtimeToUser(userId, "taxi_call_update", {
    eventType: "outgoing_call",
    rideId: ride.id,
    session: buildCallSessionPayload(session),
    signal,
  });

  queueNotification({
    userId: peerUserId,
    type: "taxi.call.incoming",
    title: "مكالمة تكسي واردة",
    body: "لديك مكالمة جديدة داخل التطبيق.",
    payload: {
      rideId: ride.id,
      callSessionId: session.id,
    },
  });

  return {
    rideId: ride.id,
    session: buildCallSessionPayload(session),
    reused: false,
  };
}

export async function sendRideCallSignal({
  rideId,
  userId,
  role,
  isSuperAdmin,
  dto,
}) {
  const ride = await repo.getRideById(rideId);
  await ensureRideCallParticipant({ ride, userId, role, isSuperAdmin });

  let session = dto.sessionId
    ? await repo.getRideCallSessionById(dto.sessionId)
    : await repo.getActiveRideCallSession(ride.id);
  if (!session || Number(session.rideRequestId) !== Number(ride.id)) {
    throw new AppError("TAXI_CALL_SESSION_NOT_FOUND", { status: 404 });
  }

  if (
    ![session.initiatorUserId, session.receiverUserId].includes(Number(userId))
  ) {
    throw new AppError("TAXI_CALL_FORBIDDEN", { status: 403 });
  }

  const signal = await repo.insertRideCallSignal({
    callSessionId: session.id,
    rideRequestId: ride.id,
    senderUserId: userId,
    signalType: dto.signalType,
    signalPayload: dto.signalPayload || null,
  });

  if (dto.signalType === "accept" || dto.signalType === "answer") {
    const answered = await repo.markRideCallAnswered({
      sessionId: session.id,
      answeredByUserId: userId,
    });
    if (answered) session = answered;
  } else if (dto.signalType === "hangup") {
    const ended = await repo.endRideCallSession({
      sessionId: session.id,
      endedByUserId: userId,
      endReason: "hangup",
      status: "ended",
    });
    if (ended) session = ended;
  } else if (dto.signalType === "decline") {
    const ended = await repo.endRideCallSession({
      sessionId: session.id,
      endedByUserId: userId,
      endReason: "decline",
      status: "declined",
    });
    if (ended) session = ended;
  }

  const peerUserId =
    Number(session.initiatorUserId) === Number(userId)
      ? Number(session.receiverUserId)
      : Number(session.initiatorUserId);

  const updatePayload = {
    eventType: "call_signal",
    rideId: ride.id,
    session: buildCallSessionPayload(session),
    signal,
  };

  void emitRealtimeToUser(peerUserId, "taxi_call_update", updatePayload);
  void emitRealtimeToUser(userId, "taxi_call_update", updatePayload);

  if (dto.signalType === "decline" || dto.signalType === "hangup") {
    queueNotification({
      userId: peerUserId,
      type: "taxi.call.ended",
      title: dto.signalType === "decline" ? "تم رفض المكالمة" : "انتهت المكالمة",
      body: dto.signalType === "decline" ? "الطرف الآخر رفض المكالمة." : "تم إنهاء المكالمة.",
      payload: {
        rideId: ride.id,
        callSessionId: session.id,
      },
    });
  }

  return {
    rideId: ride.id,
    session: buildCallSessionPayload(session),
    signal,
  };
}

export async function endRideCall({
  rideId,
  userId,
  role,
  isSuperAdmin,
  dto,
}) {
  const ride = await repo.getRideById(rideId);
  await ensureRideCallParticipant({ ride, userId, role, isSuperAdmin });

  const active = await repo.getActiveRideCallSession(ride.id);
  if (!active) {
    return { rideId: ride.id, session: null, ended: false };
  }

  if (
    ![active.initiatorUserId, active.receiverUserId].includes(Number(userId))
  ) {
    throw new AppError("TAXI_CALL_FORBIDDEN", { status: 403 });
  }

  const ended = await repo.endRideCallSession({
    sessionId: active.id,
    endedByUserId: userId,
    endReason: dto?.reason || "hangup",
    status: dto?.status || "ended",
  });

  const signalType =
    (dto?.status || "").toLowerCase() === "declined" ? "decline" : "hangup";
  const signal = await repo.insertRideCallSignal({
    callSessionId: active.id,
    rideRequestId: ride.id,
    senderUserId: userId,
    signalType,
    signalPayload: {
      reason: dto?.reason || null,
      status: dto?.status || "ended",
    },
  });

  const peerUserId =
    Number(active.initiatorUserId) === Number(userId)
      ? Number(active.receiverUserId)
      : Number(active.initiatorUserId);

  const payload = {
    eventType: "call_ended",
    rideId: ride.id,
    session: buildCallSessionPayload(ended || active),
    signal,
  };
  void emitRealtimeToUser(peerUserId, "taxi_call_update", payload);
  void emitRealtimeToUser(userId, "taxi_call_update", payload);

  return {
    rideId: ride.id,
    session: buildCallSessionPayload(ended || active),
    signal,
    ended: true,
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
      radiusM: dto.radiusM || FIRST_SEARCH_RADIUS_M,
      limit: 30,
    });
  }

  const eligibility = await loadCaptainTaxiEligibility(captainUserId).catch(
    () => null
  );
  if (eligibility && !eligibility.canReceiveRideRequests) {
    nearbyRequests = [];
  }

  return {
    presence,
    nearbyRequests,
    eligibility,
  };
}

export async function listNearbyCaptainsForCustomer(customerUserId, query) {
  await processSearchingLifecycleAndEmit();
  const current = await repo.getCustomerCurrentRide(customerUserId);
  const forceFocusRide = current?.id || null;
  const items = await repo.listNearbyCaptainMarkers({
    latitude: query.latitude,
    longitude: query.longitude,
    radiusM: query.radiusM,
    limit: query.limit,
  });

  return {
    items,
    total: items.length,
    focusedRideId: forceFocusRide,
  };
}

export async function listNearbyRequestsForCaptain(captainUserId, query) {
  await assertCaptainSubscriptionAccess(captainUserId);
  await processSearchingLifecycleAndEmit();

  const readiness = await loadCaptainTaxiActionability(captainUserId);
  if (!readiness.canReceiveRideRequests) {
    return {
      items: [],
      total: 0,
      eligibility: readiness,
    };
  }

  const items = await repo.listNearbyOpenRidesForCaptain(captainUserId, {
    radiusM: query.radiusM,
    limit: query.limit,
  });

  return {
    items,
    total: items.length,
    eligibility: readiness,
  };
}

export async function submitBid({ captainUserId, rideId, dto }) {
  await assertCaptainSubscriptionAccess(captainUserId);
  await assertCaptainCanReceiveRideRequests(captainUserId);
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
    radiusM: Math.max(ride.searchRadiusM, FIRST_SEARCH_RADIUS_M),
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

  const refreshedRide = await repo.getRideById(ride.id);
  const bids = await repo.listRideBids(ride.id);
  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: refreshedRide?.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: refreshedRide?.currentBidId,
    bidQueue,
  });
  const myQueueItem = bidQueue.queue.find(
    (entry) => Number(entry.bidId) === Number(bid.id)
  );
  const isCurrentBid = myQueueItem?.isCurrent === true;
  const offer = offers.find((entry) => Number(entry.offerId) === Number(bid.id))
    || buildTaxiOfferPayload(
      {
        ...bid,
        queuePosition: myQueueItem?.queuePosition ?? null,
        isCurrent: isCurrentBid,
        isBestPrice: myQueueItem?.isBestPrice === true,
        isNearest: myQueueItem?.isNearest === true,
        isHighestRated: myQueueItem?.isHighestRated === true,
      },
      { queuePosition: myQueueItem?.queuePosition ?? null }
    );

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: captainUserId,
    eventType: isCurrentBid ? "offer_submitted_current" : "offer_submitted_waiting",
    message: isCurrentBid
      ? "وصل عرض كابتن وبدأت المفاوضة."
      : "وصل عرض كابتن وأضيف إلى قائمة العروض.",
    payload: {
      bidId: bid.id,
      offerId: bid.id,
      captainId: captainUserId,
      offeredFareIqd: bid.offeredFareIqd,
      etaMinutes: bid.etaMinutes,
      queuePosition: myQueueItem?.queuePosition ?? null,
      queueSize: bidQueue.queueSize,
      isCurrentBid,
    },
  });

  emitTaxiRealtimeEvents(ride.customerUserId, [
    "taxi_offer_received",
    "taxi_bid_update",
  ], {
    eventType: isCurrentBid ? "offer_received_current" : "offer_received_waiting",
    rideId: ride.id,
    offer,
    bid,
    bidQueue,
    offers,
    isCurrentBid,
  });

  queueNotification({
    userId: ride.customerUserId,
    type: "taxi.offer.received",
    title: isCurrentBid
      ? "وصل عرض جديد وجاهز للتفاوض"
      : "وصل عرض جديد ضمن قائمة العروض",
    body: `عرض ${bid.offeredFareIqd} د.ع`,
    payload: {
      rideId: ride.id,
      bidId: bid.id,
      offerId: bid.id,
      offeredFareIqd: bid.offeredFareIqd,
      etaMinutes: bid.etaMinutes,
      queuePosition: myQueueItem?.queuePosition ?? null,
      queueSize: bidQueue.queueSize,
      currentOfferId: bidQueue.currentOfferId,
      isCurrentBid,
      customerUserId: ride.customerUserId,
      captainId: captainUserId,
      target: "taxi_offer_received",
    },
  });

  if (!isCurrentBid) {
    queueNotification({
      userId: captainUserId,
      type: "taxi.offer.submitted",
      title: "تم إرسال عرضك",
      body: `أنت في قائمة الانتظار (${myQueueItem?.queuePosition ?? "-"} من ${bidQueue.queueSize})`,
      payload: {
        rideId: ride.id,
        bidId: bid.id,
        offerId: bid.id,
        queuePosition: myQueueItem?.queuePosition ?? null,
        queueSize: bidQueue.queueSize,
        target: "taxi_offer_received",
      },
    });
  } else {
    emitTaxiRealtimeEvents(captainUserId, [
      "taxi_offer_received",
      "taxi_bid_update",
    ], {
      eventType: "you_are_current_offer",
      rideId: ride.id,
      offer,
      bid,
      bidQueue,
      offers,
    });
  }

  return {
    rideId: ride.id,
    bid,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    isCurrentBid,
  };
}

export async function declineRideRequestByCaptain({ captainUserId, rideId }) {
  await assertCaptainSubscriptionAccess(captainUserId);
  await assertCaptainCanReceiveRideRequests(captainUserId);
  await processSearchingLifecycleAndEmit();

  const result = await repo.declineRideByCaptain({
    rideId,
    captainUserId,
  });

  if (result.code === "RIDE_NOT_FOUND") {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }
  if (result.code === "RIDE_NOT_SEARCHING") {
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }

  const ride = result.ride;
  const priceRaise = await maybePromptRidePriceRaise(ride);

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: captainUserId,
    eventType: "ride_declined_by_captain",
    message: "الكابتن رفض الطلب.",
    payload: {
      rejectedCaptainsCount: Number(ride.rejectedCaptainsCount || 0),
      priceRaiseRecommended: priceRaise.recommended === true,
    },
  });

  void emitRealtimeToUser(ride.customerUserId, "taxi_ride_update", {
    eventType: "ride_declined_by_captain",
    ride: buildCompactRidePayload(ride),
    rejectedCaptainsCount: Number(ride.rejectedCaptainsCount || 0),
    priceRaiseRecommended: priceRaise.recommended === true,
  });

  return {
    rideId: ride.id,
    rejectedCaptainsCount: Number(ride.rejectedCaptainsCount || 0),
    priceRaiseRecommended: priceRaise.recommended === true,
  };
}

export async function raiseRideFare({ customerUserId, rideId, dto }) {
  await processSearchingLifecycleAndEmit();

  const result = await repo.raiseRideFare({
    rideId,
    customerUserId,
    proposedFareIqd: dto.proposedFareIqd,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "RIDE_NOT_PRICE_RAISE_REQUIRED") {
      throw new AppError("TAXI_RIDE_NOT_PRICE_RAISE_REQUIRED", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    if (result.code === "FARE_NOT_INCREASED") {
      throw new AppError("TAXI_FARE_NOT_INCREASED", {
        status: 409,
        details: { currentFare: result.currentFare },
      });
    }
    throw new AppError("TAXI_RIDE_FARE_RAISE_FAILED", { status: 500 });
  }

  const ride = result.ride;
  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "fare_raised",
    message: "تم رفع الأجرة لإعادة البحث عن كابتن.",
    payload: {
      previousFareIqd: result.previousFareIqd,
      nextFareIqd: result.nextFareIqd,
      pricingRound: Number(ride.pricingRound || 1),
      fareVersion: Number(ride.fareVersion || 1),
    },
  });

  const nearbyCaptainsCount = await notifyCaptainsNearRide(ride);
  await emitRideUpdate(ride, "fare_raised", {
    previousFareIqd: result.previousFareIqd,
    nextFareIqd: result.nextFareIqd,
    nearbyCaptainsCount,
  });

  queueNotification({
    userId: customerUserId,
    type: "taxi.ride.fare_raised",
    title: "تم رفع الأجرة",
    body: "أعدنا فتح البحث عن كابتن بالقيمة الجديدة.",
    payload: {
      rideId: ride.id,
      previousFareIqd: result.previousFareIqd,
      nextFareIqd: result.nextFareIqd,
      pricingRound: Number(ride.pricingRound || 1),
    },
  });

  return {
    ride: buildTaxiRideCompatView(ride),
    assignment: buildTaxiAssignmentPayload(ride),
    nearbyCaptainsCount,
    previousFareIqd: result.previousFareIqd,
    nextFareIqd: result.nextFareIqd,
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
    if (result.code === "CAPTAIN_ALREADY_ASSIGNED") {
      throw new AppError("TAXI_ALREADY_ASSIGNED", { status: 409 });
    }
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }

  const ride = result.ride;
  const latestLocation = await repo.getLatestRideLocation(ride.id);
  const rideView = buildTaxiRideCompatView(ride, { latestLocation });
  const bids = await repo.listRideBids(ride.id);
  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });
  const acceptedBid =
    result.acceptedBid ||
    bids.find((entry) => Number(entry.id) === Number(bidId)) ||
    null;
  const acceptedOffer =
    offers.find((entry) => Number(entry.offerId) === Number(bidId)) ||
    buildTaxiOfferPayload(
      {
        ...(acceptedBid || {}),
        id: bidId,
        rideRequestId: ride.id,
        captainUserId: ride.assignedCaptainUserId,
        offeredFareIqd: ride.agreedFareIqd || ride.proposedFareIqd,
        status: "accepted",
      },
      {}
    );

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "offer_accepted",
    message: "تم قبول عرض الكابتن.",
    payload: {
      acceptedBidId: ride.acceptedBidId,
      acceptedOfferId: ride.acceptedBidId,
      assignedCaptainUserId: ride.assignedCaptainUserId,
      captainId: ride.assignedCaptainUserId,
      agreedFareIqd: ride.agreedFareIqd,
      customerUserId: ride.customerUserId,
    },
  });

  emitTaxiRealtimeEvents(ride.customerUserId, [
    "taxi_offer_accepted",
    "taxi_ride_assigned",
    "taxi_ride_update",
  ], {
    eventType: "offer_accepted",
    rideId: ride.id,
    ride: rideView,
    assignment: rideView.assignment,
    acceptedBidId: ride.acceptedBidId,
    acceptedOfferId: ride.acceptedBidId,
    acceptedOffer,
    offers,
    bidQueue,
  });

  queueNotification({
    userId: ride.customerUserId,
    type: "taxi.ride.assigned",
    title: "تم تعيين الكابتن",
    body: "تم تثبيت الكابتن المختار للرحلة.",
    payload: {
      rideId: ride.id,
      offerId: ride.acceptedBidId,
      bidId: ride.acceptedBidId,
      captainId: ride.assignedCaptainUserId,
      customerUserId: ride.customerUserId,
      agreedFareIqd: ride.agreedFareIqd,
      target: "taxi_ride_assigned",
    },
  });

  if (acceptedOffer?.captainUserId) {
    emitTaxiRealtimeEvents(acceptedOffer.captainUserId, [
      "taxi_offer_accepted",
      "taxi_ride_assigned",
      "taxi_ride_update",
    ], {
      eventType: "offer_accepted",
      rideId: ride.id,
      ride: rideView,
      assignment: rideView.assignment,
      acceptedBidId: ride.acceptedBidId,
      acceptedOfferId: ride.acceptedBidId,
      acceptedOffer,
      offers,
      bidQueue,
    });

    queueNotification({
      userId: acceptedOffer.captainUserId,
      type: "taxi.offer.accepted",
      title: "تم قبول عرضك",
      body: `الزبون وافق على ${ride.agreedFareIqd || ride.proposedFareIqd} د.ع`,
      payload: {
        rideId: ride.id,
        bidId: acceptedOffer.id,
        offerId: acceptedOffer.id,
        agreedFareIqd: ride.agreedFareIqd,
        captainId: acceptedOffer.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_assigned",
      },
    });
  }

  const rejectionPayloads = [];
  for (const bid of result.bids) {
    if (bid.status !== "rejected") continue;
    rejectionPayloads.push({
      userId: bid.captainUserId,
      type: "taxi.offer.rejected",
      title: "تم اختيار كابتن آخر",
      body: "يمكنك متابعة الطلبات القريبة الجديدة.",
      payload: {
        rideId: ride.id,
        bidId: bid.id,
        offerId: bid.id,
        captainId: bid.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_unavailable",
      },
    });
    emitTaxiRealtimeEvents(bid.captainUserId, [
      "taxi_offer_rejected",
      "taxi_ride_unavailable",
      "taxi_bid_update",
    ], {
      eventType: "offer_rejected",
      rideId: ride.id,
      offerId: bid.id,
      bidId: bid.id,
      captainId: bid.captainUserId,
      customerUserId: ride.customerUserId,
      ride,
    });
  }
  queueNotifications(rejectionPayloads);

  return {
    ride: buildTaxiRideCompatView(ride, { latestLocation }),
    assignment: buildTaxiAssignmentPayload(ride, { latestLocation }),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
  };
}

export async function acceptRideByCaptain({ captainUserId, rideId }) {
  await assertCaptainSubscriptionAccess(captainUserId);
  await assertCaptainCanReceiveRideRequests(captainUserId);
  await processSearchingLifecycleAndEmit();

  const result = await repo.acceptRideByCaptain({
    captainUserId,
    rideId,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "RIDE_NOT_ACCEPTING_BIDS") {
      throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
    }
    if (result.code === "RIDE_ALREADY_ASSIGNED") {
      throw new AppError("TAXI_ALREADY_ASSIGNED", { status: 409 });
    }
    if (result.code === "CAPTAIN_ALREADY_ASSIGNED") {
      throw new AppError("TAXI_CAPTAIN_NOT_AVAILABLE", {
        status: 403,
        details: { busyRideId: result.busyRideId || null },
      });
    }
    if (result.code === "INVALID_FARE") {
      throw new AppError("TAXI_INVALID_FARE", { status: 409 });
    }
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }

  const ride = result.ride;
  const latestLocation = await repo.getLatestRideLocation(ride.id);
  const rideView = buildTaxiRideCompatView(ride, { latestLocation });
  const bids = await repo.listRideBids(ride.id);
  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });
  const acceptedOffer =
    offers.find((entry) => Number(entry.captainUserId) === Number(captainUserId)) ||
    buildTaxiOfferPayload(
      {
        ...(result.acceptedBid || {}),
        id: result.acceptedBid?.id || null,
        rideRequestId: ride.id,
        captainUserId,
        captainId: captainUserId,
        offeredFareIqd: ride.agreedFareIqd || ride.proposedFareIqd,
        status: "accepted",
      },
      {}
    );

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: captainUserId,
    eventType: "customer_fare_accepted",
    message: "قبل الكابتن أجرة الزبون مباشرة.",
    payload: {
      acceptedBidId: ride.acceptedBidId,
      acceptedOfferId: ride.acceptedBidId,
      assignedCaptainUserId: ride.assignedCaptainUserId,
      captainId: ride.assignedCaptainUserId,
      agreedFareIqd: ride.agreedFareIqd,
      customerUserId: ride.customerUserId,
    },
  });

  emitTaxiRealtimeEvents(ride.customerUserId, [
    "taxi_offer_accepted",
    "taxi_ride_assigned",
    "taxi_ride_update",
  ], {
    eventType: "customer_fare_accepted",
    rideId: ride.id,
    ride: rideView,
    assignment: rideView.assignment,
    acceptedBidId: ride.acceptedBidId,
    acceptedOfferId: ride.acceptedBidId,
    acceptedOffer,
    offers,
    bidQueue,
  });

  queueNotification({
    userId: ride.customerUserId,
    type: "taxi.ride.assigned",
    title: "تم قبول السعر",
    body: "قبل الكابتن أجرة الرحلة وتم تثبيته مباشرة.",
    payload: {
      rideId: ride.id,
      offerId: ride.acceptedBidId,
      bidId: ride.acceptedBidId,
      captainId: ride.assignedCaptainUserId,
      customerUserId: ride.customerUserId,
      agreedFareIqd: ride.agreedFareIqd,
      target: "taxi_ride_assigned",
    },
  });

  if (acceptedOffer?.captainUserId) {
    emitTaxiRealtimeEvents(acceptedOffer.captainUserId, [
      "taxi_offer_accepted",
      "taxi_ride_assigned",
      "taxi_ride_update",
    ], {
      eventType: "customer_fare_accepted",
      rideId: ride.id,
      ride: rideView,
      assignment: rideView.assignment,
      acceptedBidId: ride.acceptedBidId,
      acceptedOfferId: ride.acceptedBidId,
      acceptedOffer,
      offers,
      bidQueue,
    });
  }

  const rejectionPayloads = [];
  for (const bid of result.bids) {
    if (bid.status !== "rejected") continue;
    rejectionPayloads.push({
      userId: bid.captainUserId,
      type: "taxi.offer.rejected",
      title: "تم اختيار كابتن آخر",
      body: "تم تعيين كابتن آخر لهذه الرحلة.",
      payload: {
        rideId: ride.id,
        bidId: bid.id,
        offerId: bid.id,
        captainId: bid.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_unavailable",
      },
    });
    emitTaxiRealtimeEvents(bid.captainUserId, [
      "taxi_offer_rejected",
      "taxi_ride_unavailable",
      "taxi_bid_update",
    ], {
      eventType: "ride_assigned_to_other_captain",
      rideId: ride.id,
      offerId: bid.id,
      bidId: bid.id,
      captainId: bid.captainUserId,
      customerUserId: ride.customerUserId,
      ride,
    });
  }
  queueNotifications(rejectionPayloads);

  return {
    ride: buildTaxiRideCompatView(ride),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    acceptedBid: result.acceptedBid || null,
  };
}

export async function rejectCurrentBid({
  customerUserId,
  rideId,
  bidId = null,
}) {
  const result = await repo.rejectCurrentRideBidByCustomer({
    rideId,
    customerUserId,
    bidId,
  });

  if (result.code === "RIDE_NOT_FOUND") {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }
  if (result.code === "RIDE_NOT_ACCEPTING_BIDS") {
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }
  if (result.code === "NO_ACTIVE_BID") {
    throw new AppError("TAXI_NO_ACTIVE_BID", { status: 409 });
  }
  if (result.code === "BID_NOT_FOUND") {
    throw new AppError("TAXI_BID_NOT_FOUND", { status: 404 });
  }
  if (result.code === "BID_NOT_ACTIVE") {
    throw new AppError("TAXI_BID_NOT_ACTIVE", { status: 409 });
  }

  const ride = result.ride;
  const bids = await repo.listRideBids(ride.id);
  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });
  const rejectedOffer =
    offers.find((entry) => Number(entry.offerId) === Number(result.rejectedBid?.id)) ||
    buildTaxiOfferPayload(
      {
        ...result.rejectedBid,
        offerId: result.rejectedBid?.id || null,
        captainId: result.rejectedBid?.captainUserId || null,
        status: "rejected",
      },
      {}
    );
  const nextOffer =
    result.nextBid != null
      ? offers.find((entry) => Number(entry.offerId) === Number(result.nextBid.id)) ||
        buildTaxiOfferPayload(
          {
            ...result.nextBid,
            offerId: result.nextBid.id,
            captainId: result.nextBid.captainUserId,
            status: result.nextBid.status || "active",
          },
          {}
        )
      : null;

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "offer_rejected_by_customer",
    message: "رفض الزبون العرض الحالي وانتقل العرض التالي.",
    payload: {
      rejectedBidId: result.rejectedBid?.id || null,
      rejectedOfferId: result.rejectedBid?.id || null,
      nextBidId: result.nextBid?.id || null,
      nextOfferId: result.nextBid?.id || null,
      currentBidId: ride.currentBidId || null,
      customerUserId: ride.customerUserId,
    },
  });

  if (result.rejectedBid?.captainUserId) {
    emitTaxiRealtimeEvents(result.rejectedBid.captainUserId, [
      "taxi_offer_rejected",
      "taxi_ride_unavailable",
      "taxi_bid_update",
    ], {
      eventType: "offer_rejected_by_customer",
      rideId: ride.id,
      bidId: result.rejectedBid.id,
      offerId: result.rejectedBid.id,
      rejectedOffer,
      ride,
      customerUserId: ride.customerUserId,
    });
    queueNotification({
      userId: result.rejectedBid.captainUserId,
      type: "taxi.offer.rejected",
      title: "الزبون رفض عرضك",
      body: "تم تحويل الطلب إلى كابتن آخر في قائمة الانتظار.",
      payload: {
        rideId: ride.id,
        bidId: result.rejectedBid.id,
        offerId: result.rejectedBid.id,
        captainId: result.rejectedBid.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_unavailable",
      },
    });
  }

  if (
    result.nextBid?.captainUserId &&
    Number(result.nextBid.captainUserId) !==
      Number(result.rejectedBid?.captainUserId || 0)
  ) {
    emitTaxiRealtimeEvents(result.nextBid.captainUserId, [
      "taxi_offer_received",
      "taxi_bid_update",
    ], {
      eventType: "you_are_current_offer",
      rideId: ride.id,
      bidId: result.nextBid.id,
      offerId: result.nextBid.id,
      offer: nextOffer,
      bidQueue,
      offers,
      customerUserId: ride.customerUserId,
    });
    queueNotification({
      userId: result.nextBid.captainUserId,
      type: "taxi.offer.received",
      title: "دورك الآن للتفاوض",
      body: "أنت الآن الكابتن النشط لهذا الطلب.",
      payload: {
        rideId: ride.id,
        bidId: result.nextBid.id,
        offerId: result.nextBid.id,
        captainId: result.nextBid.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_offer_received",
      },
    });
  } else if (!result.nextBid) {
    queueNotification({
      userId: ride.customerUserId,
      type: "taxi.ride.unavailable",
      title: "لا توجد عروض حالية بعد الرفض",
      body: "سنستمر بإرسال الطلب للكباتن القريبين تلقائياً.",
      payload: {
        rideId: ride.id,
        customerUserId: ride.customerUserId,
        target: "taxi_ride_unavailable",
      },
    });
  }

  emitTaxiRealtimeEvents(ride.customerUserId, [
    "taxi_offer_rejected",
    "taxi_bid_update",
  ], {
    eventType: "offer_rejected_by_customer",
    rideId: ride.id,
    bidQueue,
    offers,
    rejectedOffer,
    nextOffer,
  });

  // `latestLocation` was referenced in the return payload below without ever
  // being declared in this function's scope, throwing a ReferenceError and
  // returning HTTP 500 to the customer AFTER the bid was already rejected and
  // realtime/notifications were already emitted (leaving the client desynced).
  // Fetch it here, mirroring acceptBid.
  const latestLocation = await repo.getLatestRideLocation(ride.id);

  return {
    ride: buildTaxiRideCompatView(ride, { latestLocation }),
    assignment: buildTaxiAssignmentPayload(ride, { latestLocation }),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    switchedToNext: !!result.nextBid,
  };
}

export async function counterOfferCurrentBid({
  customerUserId,
  rideId,
  dto,
  bidId = null,
}) {
  const result = await repo.counterOfferCurrentRideBidByCustomer({
    rideId,
    customerUserId,
    offeredFareIqd: dto.offeredFareIqd,
    note: dto.note,
    bidId,
  });

  if (result.code === "RIDE_NOT_FOUND") {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }
  if (result.code === "RIDE_NOT_ACCEPTING_BIDS") {
    throw new AppError("TAXI_RIDE_NOT_ACCEPTING_BIDS", { status: 409 });
  }
  if (result.code === "NO_ACTIVE_BID") {
    throw new AppError("TAXI_NO_ACTIVE_BID", { status: 409 });
  }
  if (result.code === "BID_NOT_FOUND") {
    throw new AppError("TAXI_BID_NOT_FOUND", { status: 404 });
  }
  if (result.code === "BID_NOT_ACTIVE") {
    throw new AppError("TAXI_BID_NOT_ACTIVE", { status: 409 });
  }

  const ride = result.ride;
  const bids = await repo.listRideBids(ride.id);
  const bidQueue = buildBidQueueMeta({
    bids,
    currentBidId: ride.currentBidId,
  });
  const offers = buildOfferPresentationList({
    bids,
    currentBidId: ride.currentBidId,
    bidQueue,
  });
  const targetOffer =
    offers.find(
      (entry) => Number(entry.offerId) === Number(result.updatedBid?.id || result.previousBid?.id || 0)
    ) ||
    buildTaxiOfferPayload(
      {
        ...result.updatedBid,
        ...result.previousBid,
        offerId: result.updatedBid?.id || result.previousBid?.id || null,
        captainId:
          result.updatedBid?.captainUserId ||
          result.previousBid?.captainUserId ||
          null,
      },
      {}
    );
  const nextOffer =
    result.nextBid != null
      ? offers.find((entry) => Number(entry.offerId) === Number(result.nextBid.id)) ||
        buildTaxiOfferPayload(
          {
            ...result.nextBid,
            offerId: result.nextBid.id,
            captainId: result.nextBid.captainUserId,
          },
          {}
        )
      : null;
  const previousCaptainUserId = Number(
    result.updatedBid?.captainUserId || result.previousBid?.captainUserId || 0
  ) || null;
  const currentCaptainUserId = await resolveNegotiationCaptainUserId(ride);

  if (result.updatedBid) {
    await repo.insertRideChatMessage({
      rideRequestId: ride.id,
      senderUserId: customerUserId,
      senderRole: "customer",
      messageType: "offer",
      messageText:
        dto.note?.trim() ||
        `عرض مضاد من الزبون: ${result.updatedBid.offeredFareIqd} د.ع`,
      offeredFareIqd: result.updatedBid.offeredFareIqd,
    });
  }

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType:
      result.code === "COUNTER_LIMIT_REACHED"
        ? "counter_offer_limit_reached"
        : "counter_offer_submitted",
    message:
      result.code === "COUNTER_LIMIT_REACHED"
        ? "انتهت جولات التفاوض لهذا الكابتن وتم التحويل للعرض التالي."
        : "تم إرسال عرض مضاد إلى الكابتن.",
    payload: {
      offeredFareIqd: dto.offeredFareIqd,
      bidId: result.updatedBid?.id || result.previousBid?.id || null,
      offerId: result.updatedBid?.id || result.previousBid?.id || null,
      switchedToNext: !!result.switchedToNext,
      nextBidId: result.nextBid?.id || null,
      nextOfferId: result.nextBid?.id || null,
      customerUserId: ride.customerUserId,
    },
  });

  if (previousCaptainUserId) {
    emitTaxiRealtimeEvents(previousCaptainUserId, [
      "taxi_counter_offer_received",
      "taxi_bid_update",
    ], {
      eventType:
        result.code === "COUNTER_LIMIT_REACHED"
          ? "counter_offer_limit_reached"
          : "counter_offer_submitted",
      rideId: ride.id,
      offeredFareIqd: dto.offeredFareIqd,
      offerId: targetOffer?.offerId || null,
      bidId: targetOffer?.bidId || null,
      offer: targetOffer,
      ride,
      customerUserId: ride.customerUserId,
      bidQueue,
      offers,
    });

    queueNotification({
      userId: previousCaptainUserId,
      type: "taxi.counter_offer.received",
      title:
        result.code === "COUNTER_LIMIT_REACHED"
          ? "انتهت جولات التفاوض"
          : "وصلك عرض مضاد من الزبون",
      body:
        result.code === "COUNTER_LIMIT_REACHED"
          ? "تم التحويل لكابتن آخر تلقائياً."
          : `السعر الجديد: ${dto.offeredFareIqd} د.ع`,
      payload: {
        rideId: ride.id,
        offeredFareIqd: dto.offeredFareIqd,
        bidId: targetOffer?.bidId || null,
        offerId: targetOffer?.offerId || null,
        captainId: previousCaptainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_counter_offer_received",
      },
    });
  }

  if (
    result.nextBid?.captainUserId &&
    Number(result.nextBid.captainUserId) !== Number(previousCaptainUserId || 0)
  ) {
    emitTaxiRealtimeEvents(result.nextBid.captainUserId, [
      "taxi_offer_received",
      "taxi_bid_update",
    ], {
      eventType: "you_are_current_offer",
      rideId: ride.id,
      bidId: result.nextBid.id,
      offerId: result.nextBid.id,
      offer: nextOffer,
      customerUserId: ride.customerUserId,
      bidQueue,
      offers,
    });
    queueNotification({
      userId: result.nextBid.captainUserId,
      type: "taxi.offer.received",
      title: "دورك الآن للتفاوض",
      body: "أنت الآن الكابتن النشط لهذا الطلب.",
      payload: {
        rideId: ride.id,
        bidId: result.nextBid.id,
        offerId: result.nextBid.id,
        captainId: result.nextBid.captainUserId,
        customerUserId: ride.customerUserId,
        target: "taxi_offer_received",
      },
    });
  } else if (
    currentCaptainUserId &&
    Number(currentCaptainUserId) !== Number(previousCaptainUserId || 0)
  ) {
    emitTaxiRealtimeEvents(currentCaptainUserId, [
      "taxi_offer_received",
      "taxi_bid_update",
    ], {
      eventType: "you_are_current_offer",
      rideId: ride.id,
      bidQueue,
      offers,
      customerUserId: ride.customerUserId,
    });
  }

  emitTaxiRealtimeEvents(ride.customerUserId, [
    "taxi_counter_offer_received",
    "taxi_bid_update",
  ], {
    eventType:
      result.code === "COUNTER_LIMIT_REACHED"
        ? "counter_offer_limit_reached"
        : "counter_offer_submitted",
    rideId: ride.id,
    bidQueue,
    offers,
    targetOffer,
    nextOffer,
    customerUserId: ride.customerUserId,
  });

  return {
    ride: buildTaxiRideCompatView(ride),
    bids,
    bidQueue,
    offers,
    offerQueue: bidQueue.offerQueue,
    currentOffer: bidQueue.currentOffer,
    currentOfferId: bidQueue.currentOfferId,
    switchedToNext: !!result.switchedToNext,
    negotiationClosed: result.code === "COUNTER_LIMIT_REACHED",
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
    eventType: "ride_canceled",
    message: "تم إلغاء الطلب من قبل الزبون.",
    payload: null,
  });

  await emitRideUpdate(result.ride, "ride_canceled");
  emitTaxiRealtimeEvents(result.ride.customerUserId, ["taxi_ride_canceled"], {
    eventType: "ride_canceled",
    rideId: result.ride.id,
    ride: buildCompactRidePayload(result.ride),
    assignment: buildTaxiAssignmentPayload(result.ride),
    customerUserId: result.ride.customerUserId,
  });

  if (result.ride.assignedCaptainUserId) {
    emitTaxiRealtimeEvents(result.ride.assignedCaptainUserId, [
      "taxi_ride_canceled",
    ], {
      eventType: "ride_canceled",
      rideId: result.ride.id,
      ride: buildCompactRidePayload(result.ride),
      assignment: buildTaxiAssignmentPayload(result.ride),
      customerUserId: result.ride.customerUserId,
      captainId: result.ride.assignedCaptainUserId,
    });
    queueNotification({
      userId: result.ride.assignedCaptainUserId,
      type: "taxi.ride.canceled",
      title: "تم إلغاء الطلب",
      body: "الزبون ألغى الرحلة قبل الإتمام.",
      payload: {
        rideId: result.ride.id,
        customerUserId: result.ride.customerUserId,
        captainId: result.ride.assignedCaptainUserId,
        target: "taxi_ride_canceled",
      },
    });
  }

  return result.ride;
}

export async function rateRideByCustomer({
  customerUserId,
  rideId,
  dto,
}) {
  const result = await repo.rateCompletedRideByCustomer({
    rideId,
    customerUserId,
    rating: dto.rating,
    review: dto.review,
  });

  if (result.code !== "OK") {
    if (result.code === "RIDE_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
    }
    if (result.code === "RIDE_NOT_COMPLETED") {
      throw new AppError("TAXI_RIDE_NOT_COMPLETED", {
        status: 409,
        details: { currentStatus: result.currentStatus },
      });
    }
    if (result.code === "RIDE_CAPTAIN_NOT_FOUND") {
      throw new AppError("TAXI_RIDE_CAPTAIN_NOT_FOUND", { status: 409 });
    }
    throw new AppError("TAXI_RIDE_RATING_FAILED", { status: 500 });
  }

  await repo.createRideEvent({
    rideRequestId: result.ride.id,
    actorUserId: customerUserId,
    eventType: "ride_rated",
    message: "تم تقييم الكابتن بعد الرحلة.",
    payload: {
      rating: result.rating,
      review: result.review,
      captainUserId: result.captainUserId,
      captainRatingAvg: result.captainRatingAvg,
      captainRatedCount: result.captainRatedCount,
    },
  });

  await emitRideUpdate(result.ride, "ride_rated", {
    rating: result.rating,
    captainRatingAvg: result.captainRatingAvg,
  });

  if (result.captainUserId) {
    queueNotification({
      userId: Number(result.captainUserId),
      type: "taxi.ride.rated",
      title: "تقييم جديد من الزبون",
      body: `حصلت على تقييم ${result.rating}/5 لهذه الرحلة.`,
      payload: {
        rideId: result.ride.id,
        rating: result.rating,
        captainRatingAvg: result.captainRatingAvg,
      },
    });
  }

  return {
    ride: result.ride,
    rating: result.rating,
    review: result.review,
    captainRatingAvg: result.captainRatingAvg,
    captainRatedCount: result.captainRatedCount,
  };
}

async function transitionRideStatus({
  captainUserId,
  rideId,
  nextStatus,
  eventType,
  notificationBody,
  realtimeEventNames = [],
  notificationType = null,
}) {
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

  if (realtimeEventNames.length > 0) {
    const payload = {
      eventType,
      rideId: result.ride.id,
      ride: buildCompactRidePayload(result.ride),
      assignment: buildTaxiAssignmentPayload(result.ride),
      previousStatus: result.previousStatus,
    };
    emitTaxiRealtimeEvents(result.ride.customerUserId, realtimeEventNames, payload);
    if (result.ride.assignedCaptainUserId) {
      emitTaxiRealtimeEvents(
        result.ride.assignedCaptainUserId,
        realtimeEventNames,
        payload
      );
    }
  }

  queueNotification({
    userId: result.ride.customerUserId,
    type: notificationType || `taxi.ride.${eventType}`,
    title: "تحديث على رحلة التكسي",
    body: notificationBody,
    payload: {
      rideId: result.ride.id,
      status: result.ride.status,
      customerUserId: result.ride.customerUserId,
      captainId: result.ride.assignedCaptainUserId || null,
      target:
        realtimeEventNames[0] ||
        (notificationType ? notificationType.replace(/\./g, "_") : null),
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
    realtimeEventNames: ["taxi_captain_arrived"],
    notificationType: "taxi.captain.arrived",
  });
}

export async function startRide({ captainUserId, rideId }) {
  return transitionRideStatus({
    captainUserId,
    rideId,
    nextStatus: "ride_started",
    eventType: "ride_started",
    notificationBody: "بدأت الرحلة، يمكنك متابعة السيارة مباشرة.",
    realtimeEventNames: ["taxi_ride_started"],
    notificationType: "taxi.ride.started",
  });
}

export async function completeRide({ captainUserId, rideId }) {
  const ride = await transitionRideStatus({
    captainUserId,
    rideId,
    nextStatus: "completed",
    eventType: "ride_completed",
    notificationBody: "تم إكمال الرحلة بنجاح.",
    realtimeEventNames: ["taxi_ride_completed"],
    notificationType: "taxi.ride.completed",
  });

  queueNotification({
    userId: captainUserId,
    type: "taxi.ride.completed",
    title: "تم إنهاء الرحلة",
    body: "تم تسجيل الرحلة كمكتملة.",
    payload: {
      rideId: ride.id,
      status: ride.status,
      customerUserId: ride.customerUserId,
      captainId: ride.assignedCaptainUserId || captainUserId,
      target: "taxi_ride_completed",
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
    void emitRealtimeToUser(ride.customerUserId, "taxi_location_update", {
      rideId: ride.id,
      status: ride.status,
      location: result.location,
    });

    if (ride.assignedCaptainUserId) {
      void emitRealtimeToUser(ride.assignedCaptainUserId, "taxi_location_update", {
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

  const latest = await repo.getLatestRideLocation(ride.id);
  const target = latest || ride.pickup;
  const wazeLink = target
    ? `https://waze.com/ul?ll=${target.latitude},${target.longitude}&navigate=yes`
    : null;

  return {
    ...out,
    publicPath: `/api/taxi/public/track/${out.token}`,
    wazeLink,
  };
}

export async function listRideSharedFriends({ customerUserId, rideId }) {
  const ride = await repo.getRideByIdForCustomer(rideId, customerUserId);
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  const items = await repo.listRideFriendShares({
    rideId: ride.id,
    customerUserId,
  });
  return {
    rideId: ride.id,
    items,
    total: items.length,
  };
}

export async function shareRideWithFriends({
  customerUserId,
  rideId,
  friendUserIds = [],
}) {
  const ride = await repo.getRideByIdForCustomer(rideId, customerUserId);
  if (!ride) {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }

  const uniqueFriendIds = [...new Set((friendUserIds || []).map((v) => Number(v)))]
    .filter((v) => Number.isInteger(v) && v > 0)
    .filter((v) => Number(v) !== Number(customerUserId));
  if (uniqueFriendIds.length === 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["friendUserIds"] },
    });
  }

  const items = [];
  for (const friendUserId of uniqueFriendIds) {
    const item = await repo.upsertRideFriendShare({
      rideId: ride.id,
      customerUserId,
      friendUserId,
    });
    if (item) items.push(item);
  }

  await repo.createRideEvent({
    rideRequestId: ride.id,
    actorUserId: customerUserId,
    eventType: "ride_shared_with_friends",
    message: "تمت مشاركة الرحلة مع أصدقاء.",
    payload: {
      total: items.length,
      friendUserIds: items.map((item) => Number(item.friendUserId)),
    },
  });

  for (const item of items) {
    queueNotification({
      userId: Number(item.friendUserId),
      type: "taxi.ride.shared",
      title: "تمت مشاركة رحلة تكسي معك",
      body: "يمكنك متابعة الرحلة مباشرة.",
      payload: {
        rideId: ride.id,
        customerUserId: Number(customerUserId),
      },
    });
    void emitRealtimeToUser(Number(item.friendUserId), "taxi_ride_shared", {
      rideId: ride.id,
      customerUserId: Number(customerUserId),
      friendUserId: Number(item.friendUserId),
      status: ride.status,
    });
  }

  return {
    rideId: ride.id,
    items,
    total: items.length,
  };
}

export async function getSharedRideTrackForFriend({ friendUserId, rideId }) {
  const data = await repo.getSharedRideTrackForFriend({ friendUserId, rideId });
  if (!data) {
    throw new AppError("TAXI_TRACK_NOT_FOUND", { status: 404 });
  }

  const events = await repo.listRideEvents(data.ride.id, { limit: 50 });

  return {
    ride: buildTaxiRideCompatView(data.ride, { latestLocation: data.location }),
    assignment: buildTaxiAssignmentPayload(data.ride, { latestLocation: data.location }),
    latestLocation: data.location,
    share: data.share,
    events: [...events].reverse(),
  };
}

export async function getPublicTrack(token) {
  const data = await repo.getPublicTrackByToken(token);
  if (!data) {
    throw new AppError("TAXI_TRACK_NOT_FOUND", { status: 404 });
  }

  const events = await repo.listRideEvents(data.ride.id, { limit: 50 });

  return {
    ride: buildTaxiRideCompatView(data.ride, { latestLocation: data.location }),
    assignment: buildTaxiAssignmentPayload(data.ride, { latestLocation: data.location }),
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
  const [subscriptionContext, eligibility] = await Promise.all([
    loadCaptainSubscriptionContext(captainUserId),
    loadCaptainTaxiEligibility(captainUserId),
  ]);
  return {
    profile: subscriptionContext.profile,
    subscription: subscriptionContext.subscription,
    eligibility,
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

  let request;
  try {
    request = await repo.createCaptainProfileEditRequest({
      captainUserId,
      requestedChanges: changes,
      captainNote: dto?.captainNote || null,
    });
  } catch (error) {
    if (String(error?.code || "").toUpperCase() === "42P01") {
      throw new AppError("TAXI_PROFILE_EDIT_NOT_AVAILABLE", { status: 503 });
    }
    throw error;
  }

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

export async function listPendingCaptainProfileEditRequests({ limit = 100 } = {}) {
  try {
    const rows = await repo.listPendingCaptainProfileEditRequests({ limit });
    return rows.map(mapCaptainProfileEditRequest);
  } catch (error) {
    if (String(error?.code || "").toUpperCase() === "42P01") {
      return [];
    }
    throw error;
  }
}

export async function reviewCaptainProfileEditRequestByAdmin({
  requestId,
  decision,
  adminUserId,
  adminNote = null,
}) {
  const normalizedDecision = String(decision || "").trim().toLowerCase();
  if (!["approved", "rejected"].includes(normalizedDecision)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["decision"] },
    });
  }

  let reviewed;
  try {
    reviewed = await repo.reviewCaptainProfileEditRequestByAdmin({
      requestId: Number(requestId),
      decision: normalizedDecision,
      adminUserId: Number(adminUserId?.userId || adminUserId),
      adminNote,
    });
  } catch (error) {
    if (String(error?.code || "").toUpperCase() === "42P01") {
      throw new AppError("TAXI_PROFILE_EDIT_NOT_AVAILABLE", { status: 503 });
    }
    throw error;
  }

  if (!reviewed) {
    throw new AppError("TAXI_PROFILE_EDIT_REQUEST_NOT_FOUND", { status: 404 });
  }
  if (reviewed.alreadyReviewed === true) {
    throw new AppError("TAXI_PROFILE_EDIT_ALREADY_REVIEWED", { status: 409 });
  }

  const request = reviewed.request || {};
  return {
    id: Number(request.id || requestId),
    captainUserId: Number(request.captain_user_id || 0),
    status: String(request.status || normalizedDecision).trim().toLowerCase(),
    adminNote: request.admin_note || null,
    requestedAt: request.requested_at || null,
    reviewedAt: request.reviewed_at || null,
    requestedChanges:
      request.requested_changes && typeof request.requested_changes === "object"
        ? request.requested_changes
        : {},
    captain: mapCaptainProfile(reviewed.captain),
  };
}

export async function getCaptainDashboard(captainUserId, query = {}) {
  const period = String(query?.period || "month").toLowerCase();
  const safePeriod = ["day", "week", "month", "all"].includes(period)
    ? period
    : "month";
  const limit = Math.max(1, Math.min(200, Number(query?.limit) || 40));

  const [profileRow, metricsRow, history, subscriptionRaw, eligibility] =
    await Promise.all([
    repo.getCaptainProfile(captainUserId),
    repo.getCaptainDashboardMetrics(captainUserId),
    repo.listCaptainRideHistoryByPeriod(captainUserId, {
      period: safePeriod,
      limit,
    }),
    repo.getCaptainSubscription(captainUserId),
    loadCaptainTaxiEligibility(captainUserId),
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
    eligibility,
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
      plateGovernorate: row.plate_governorate || null,
      plateCategory: row.plate_category || null,
      plateLetter: row.plate_letter || null,
      plateDigits: row.plate_digits || null,
      cashPaymentRequestedAt: row.cash_payment_requested_at || null,
      subscription,
    };
  });
}

