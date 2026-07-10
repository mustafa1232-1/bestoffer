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
    searchRadiusM: 2000,
    rejectedCaptainsCount: 0,
    priceRaiseRecommended: false,
    priceRaisePromptedAt: null,
    finalAcceptanceDeadlineAt: null,
    captainRating: null,
    captainReview: null,
    captainRatedAt: null,
    createdAt: "2026-07-10T00:00:00.000Z",
    updatedAt: "2026-07-10T00:00:00.000Z",
  });

  assert.equal(payload.displayState, "negotiating");
  assert.equal(payload.isActiveRide, false);
  assert.equal(payload.isSearchingRide, true);
  assert.equal(payload.isNegotiatingRide, true);
  assert.equal(payload.isTerminalRide, false);
  assert.equal(payload.currentBidId, 44);
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
