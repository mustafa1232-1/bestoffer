import assert from "node:assert/strict";
import test from "node:test";

import { __taxiMappersTestApi, resolveTaxiRideDisplayState } from "../modules/taxi/taxi.mappers.js";
import { __taxiServiceTestApi } from "../modules/taxi/taxi.service.js";
import { validateCreateRide } from "../modules/taxi/taxi.validators.js";

test("taxi create-ride validation rejects missing pickup coordinates and zero fare", () => {
  const missingPickup = validateCreateRide({
    dropoffLatitude: 33.32,
    dropoffLongitude: 44.37,
    pickupLabel: "Pickup",
    dropoffLabel: "Dropoff",
    proposedFareIqd: 10000,
  });

  assert.equal(missingPickup.ok, false);
  assert.equal(missingPickup.errors.pickupLatitude, "SELECT_LOCATION");
  assert.equal(missingPickup.errors.pickupLongitude, "SELECT_LOCATION");

  const missingDropoff = validateCreateRide({
    pickupLatitude: 33.31,
    pickupLongitude: 44.36,
    pickupLabel: "Pickup",
    dropoffLabel: "Dropoff",
    proposedFareIqd: 10000,
  });

  assert.equal(missingDropoff.ok, false);
  assert.equal(missingDropoff.errors.dropoffLatitude, "SELECT_LOCATION");
  assert.equal(missingDropoff.errors.dropoffLongitude, "SELECT_LOCATION");

  const missingPickupLabel = validateCreateRide({
    pickupLatitude: 33.31,
    pickupLongitude: 44.36,
    dropoffLatitude: 33.32,
    dropoffLongitude: 44.37,
    pickupLabel: "",
    dropoffLabel: "Dropoff",
    proposedFareIqd: 10000,
  });

  assert.equal(missingPickupLabel.ok, false);
  assert.equal(missingPickupLabel.errors.pickupLabel, "REQUIRED");

  const missingDropoffLabel = validateCreateRide({
    pickupLatitude: 33.31,
    pickupLongitude: 44.36,
    dropoffLatitude: 33.32,
    dropoffLongitude: 44.37,
    pickupLabel: "Pickup",
    dropoffLabel: "   ",
    proposedFareIqd: 10000,
  });

  assert.equal(missingDropoffLabel.ok, false);
  assert.equal(missingDropoffLabel.errors.dropoffLabel, "REQUIRED");

  const zeroFare = validateCreateRide({
    pickupLatitude: 33.31,
    pickupLongitude: 44.36,
    dropoffLatitude: 33.32,
    dropoffLongitude: 44.37,
    pickupLabel: "Pickup",
    dropoffLabel: "Dropoff",
    proposedFareIqd: 0,
  });

  assert.equal(zeroFare.ok, false);
  assert.equal(zeroFare.errors.proposedFareIqd, "INVALID_NUMBER");
});

test("taxi ride display state keeps searching, active, and terminal states distinct", () => {
  assert.equal(resolveTaxiRideDisplayState({ status: "searching" }), "searching");
  assert.equal(
    resolveTaxiRideDisplayState({ status: "price_raise_required" }),
    "price_raise_required"
  );
  assert.equal(
    resolveTaxiRideDisplayState({ status: "searching", currentBidId: null }),
    "searching"
  );
  assert.equal(
    resolveTaxiRideDisplayState({ status: "searching", currentBidId: 7 }),
    "negotiating"
  );
  assert.equal(resolveTaxiRideDisplayState({ status: "captain_assigned" }), "active");
  assert.equal(resolveTaxiRideDisplayState({ status: "ride_started" }), "active");
  assert.equal(resolveTaxiRideDisplayState({ status: "completed" }), "terminal");
});

test("taxi compact payload preserves display state flags for public consumers", () => {
  const payload = __taxiServiceTestApi.buildCompactRidePayload({
    id: 9,
    status: "searching",
    displayState: "negotiating",
    isActiveRide: false,
    isSearchingRide: true,
    isNegotiatingRide: true,
    isTerminalRide: false,
    proposedFareIqd: 12000,
    agreedFareIqd: null,
    currentBidId: 44,
    pickup: { label: "Pickup" },
    dropoff: { label: "Dropoff" },
    customerUserId: 7,
    assignedCaptainUserId: null,
    searchPhase: "captains_searching",
    rejectedCaptainsCount: 0,
    priceRaiseRecommended: false,
    priceRaisePromptedAt: null,
    finalAcceptanceDeadlineAt: null,
    captainRating: null,
    captainReview: null,
    captainRatedAt: null,
    pricingRound: 1,
    previousProposedFareIqd: 11000,
    priceRaiseRequiredAt: "2026-07-10T00:01:00.000Z",
    fareVersion: 2,
    priceRaiseRequired: true,
    isPriceRaiseRequiredRide: true,
    searchRadiusM: 15000,
    createdAt: "2026-07-10T00:00:00.000Z",
    updatedAt: "2026-07-10T00:00:00.000Z",
  });

  assert.equal(payload.displayState, "negotiating");
  assert.equal(payload.isActiveRide, false);
  assert.equal(payload.isSearchingRide, true);
  assert.equal(payload.isNegotiatingRide, true);
  assert.equal(payload.isTerminalRide, false);
  assert.equal(payload.currentBidId, 44);
  assert.equal(payload.pricingRound, 1);
  assert.equal(payload.priceRaiseRequired, true);
  assert.equal(payload.isPriceRaiseRequiredRide, true);
});

test("taxi offer helpers preserve multi-captain offer presentation and queue metadata", () => {
  const bids = [
    {
      id: 11,
      rideRequestId: 41,
      captainUserId: 21,
      offeredFareIqd: 14500,
      etaMinutes: 6,
      note: "Closer to pickup",
      status: "active",
      counterOfferCount: 1,
      lastOfferIqd: 14500,
      lastOfferBy: "captain",
      createdAt: "2026-07-11T09:00:00.000Z",
      updatedAt: "2026-07-11T09:01:00.000Z",
      distanceM: 900,
      captain: { ratingAvg: 4.9, fullName: "Captain One" },
    },
    {
      id: 12,
      rideRequestId: 41,
      captainUserId: 22,
      offeredFareIqd: 15100,
      etaMinutes: 8,
      note: "Ready now",
      status: "active",
      counterOfferCount: 0,
      lastOfferIqd: 15100,
      lastOfferBy: "captain",
      createdAt: "2026-07-11T09:02:00.000Z",
      updatedAt: "2026-07-11T09:02:30.000Z",
      distanceM: 1500,
      captain: { ratingAvg: 4.7, fullName: "Captain Two" },
    },
  ];

  const bidQueue = __taxiServiceTestApi.buildBidQueueMeta({
    bids,
    currentBidId: 11,
  });
  const offers = __taxiServiceTestApi.buildOfferPresentationList({
    bids,
    currentBidId: 11,
    bidQueue,
  });

  assert.equal(bidQueue.queueSize, 2);
  assert.equal(bidQueue.currentOfferId, 11);
  assert.equal(bidQueue.queue[0].bidId, 11);
  assert.equal(bidQueue.queue[0].offerId, 11);
  assert.equal(bidQueue.queue[0].isCurrent, true);
  assert.equal(bidQueue.queue[0].isBestPrice, true);
  assert.equal(bidQueue.queue[0].isNearest, true);
  assert.equal(bidQueue.queue[0].isHighestRated, true);

  const firstOffer = offers.find((offer) => offer.offerId === 11);
  const secondOffer = offers.find((offer) => offer.offerId === 12);

  assert.ok(firstOffer);
  assert.ok(secondOffer);
  assert.equal(firstOffer.bidId, 11);
  assert.equal(firstOffer.captainId, 21);
  assert.equal(firstOffer.queuePosition, 1);
  assert.equal(firstOffer.isCurrent, true);
  assert.equal(firstOffer.isBestPrice, true);
  assert.equal(firstOffer.isNearest, true);
  assert.equal(firstOffer.isHighestRated, true);
  assert.equal(secondOffer.queuePosition, 2);
  assert.equal(secondOffer.captainId, 22);
  assert.equal(secondOffer.isCurrent, false);
  assert.equal(secondOffer.isBestPrice, false);
});

test("taxi captain eligibility requires approved, online, and complete profile", () => {
  const now = new Date().toISOString();
  const completeProfile = {
    id: 31,
    full_name: "Captain Complete",
    phone: "07711111111",
    vehicle_type: "sedan",
    car_model: "Corolla",
    car_color: "White",
    plate_number: "BGD-123",
    delivery_account_approved: true,
    is_active: true,
    rating_avg: 4.8,
    rides_count: 29,
  };

  const eligible = __taxiServiceTestApi.buildCaptainTaxiEligibility({
    profileRow: completeProfile,
    presenceRow: {
      captain_user_id: 31,
      isOnline: true,
      latitude: 33.31,
      longitude: 44.36,
      lastSeenAt: now,
    },
  });

  assert.equal(eligible.canReceiveRideRequests, true);
  assert.equal(eligible.isApproved, true);
  assert.equal(eligible.isActive, true);
  assert.equal(eligible.isOnline, true);
  assert.equal(eligible.isProfileComplete, true);
  assert.deepEqual(eligible.reasons, []);

  const blocked = __taxiServiceTestApi.buildCaptainTaxiEligibility({
    profileRow: {
      ...completeProfile,
      phone: "",
    },
    presenceRow: {
      captain_user_id: 31,
      isOnline: true,
      latitude: 33.31,
      longitude: 44.36,
      lastSeenAt: "2020-01-01T00:00:00.000Z",
    },
  });

  assert.equal(blocked.canReceiveRideRequests, false);
  assert.ok(blocked.reasons.includes("profile_incomplete"));
  assert.ok(blocked.reasons.includes("offline"));
});

test("taxi chat access stays blocked until a ride is actually assigned", async () => {
  await assert.rejects(
    () =>
      __taxiServiceTestApi.ensureRideChatAccess({
        ride: {
          id: 11,
          customerUserId: 7,
          assignedCaptainUserId: null,
        },
        userId: 7,
        role: "user",
        isSuperAdmin: false,
      }),
    (error) => error?.message === "TAXI_RIDE_FORBIDDEN" && error?.status === 403
  );

  const customerAccess = await __taxiServiceTestApi.ensureRideChatAccess({
    ride: {
      id: 11,
      customerUserId: 7,
      assignedCaptainUserId: 18,
    },
    userId: 7,
    role: "user",
    isSuperAdmin: false,
  });
  assert.equal(customerAccess.senderRole, "customer");

  const captainAccess = await __taxiServiceTestApi.ensureRideChatAccess({
    ride: {
      id: 11,
      customerUserId: 7,
      assignedCaptainUserId: 18,
    },
    userId: 18,
    role: "taxi_captain",
    isSuperAdmin: false,
  });
  assert.equal(captainAccess.senderRole, "captain");
});

test("taxi test api exposes the expected helper surface", () => {
  assert.equal(typeof __taxiMappersTestApi.resolveTaxiRideDisplayState, "function");
  assert.equal(typeof __taxiServiceTestApi.buildCompactRidePayload, "function");
});

test("taxi assignment payload exposes canonical ride, captain, and vehicle data", () => {
  const assignment = __taxiServiceTestApi.buildTaxiAssignmentPayload(
    {
      id: 41,
      status: "captain_assigned",
      customerFare: 14500,
      finalFare: 16000,
      currency: "IQD",
      pickup: {
        latitude: 33.31456,
        longitude: 44.36611,
        label: "Bismayah Gate",
      },
      dropoff: {
        latitude: 33.32091,
        longitude: 44.39118,
        label: "Central Mall",
      },
      assignedCaptainUserId: 77,
      captain: {
        id: 77,
        fullName: "Captain Noor",
        profileImageUrl: "https://cdn.example.com/captain.jpg",
        phone: "07711111111",
        ratingAvg: 4.9,
        ridesCount: 128,
        carMake: "Toyota",
        carModel: "Corolla",
        carYear: 2022,
        carColor: "Silver",
        vehicleType: "sedan",
        plateNumber: "TX-001",
        carImageUrl: "https://cdn.example.com/car.jpg",
      },
      updatedAt: "2026-07-12T12:00:00.000Z",
      assignedAt: "2026-07-12T11:59:00.000Z",
    },
    {
      latestLocation: {
        latitude: 33.315,
        longitude: 44.367,
        headingDeg: 90,
      },
    }
  );

  assert.equal(assignment.rideId, 41);
  assert.equal(assignment.status, "captain_assigned");
  assert.equal(assignment.customerFare, 14500);
  assert.equal(assignment.finalFare, 16000);
  assert.equal(assignment.pickupAddress, "Bismayah Gate");
  assert.equal(assignment.destinationAddress, "Central Mall");
  assert.equal(assignment.captain.captainName, "Captain Noor");
  assert.equal(assignment.captain.captainPhone, "07711111111");
  assert.equal(assignment.captain.captainDistanceMeters >= 0, true);
  assert.equal(assignment.vehicle.vehicleMake, "Toyota");
  assert.equal(assignment.vehicle.vehicleModel, "Corolla");
  assert.equal(assignment.vehicle.vehiclePlate, "TX-001");
});
