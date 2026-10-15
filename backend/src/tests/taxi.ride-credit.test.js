import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import * as taxiRepo from "../modules/taxi/taxi.repo.js";
import * as taxiService from "../modules/taxi/taxi.service.js";
import { hashPin } from "../shared/utils/hash.js";

function suffix(prefix) {
  return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

async function createActor(role) {
  const pinHash = await hashPin("1234");
  return createUser({
    fullName: suffix(role).slice(0, 24),
    username: suffix(role).slice(0, 24),
    phone: `07${Math.floor(10_000_000 + Math.random() * 89_000_000)}`,
    pinHash,
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "taxi_ride_credit_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function makeCaptainReady(captainUserId) {
  await q(
    `UPDATE app_user
     SET taxi_account_approved = TRUE,
         delivery_account_approved = TRUE
     WHERE id = $1`,
    [Number(captainUserId)]
  );
  await q(
    `INSERT INTO taxi_captain_profile
       (user_id, vehicle_type, car_make, car_model, car_year, car_color, plate_number, is_active)
     VALUES ($1, 'sedan', 'Toyota', 'Corolla', 2022, 'White', $2, TRUE)
     ON CONFLICT (user_id)
     DO UPDATE SET is_active = TRUE, updated_at = NOW()`,
    [Number(captainUserId), suffix("PL")]
  );
  await taxiRepo.upsertCaptainPresence({
    captainUserId,
    isOnline: true,
    latitude: 33.19302,
    longitude: 44.62071,
    headingDeg: 0,
    speedKmh: 0,
    accuracyM: 5,
  });
}

async function cleanup(ids) {
  const userIds = ids.filter((id) => Number.isInteger(Number(id)));
  if (userIds.length === 0) return;
  await q(
    `DELETE FROM taxi_captain_ride_credit_ledger
     WHERE captain_user_id = ANY($1::bigint[])`,
    [userIds]
  );
  await q(
    `DELETE FROM taxi_ride_request
     WHERE customer_user_id = ANY($1::bigint[])
        OR assigned_captain_user_id = ANY($1::bigint[])`,
    [userIds]
  );
  await q(
    `DELETE FROM taxi_captain_presence
     WHERE captain_user_id = ANY($1::bigint[])`,
    [userIds]
  );
  await q(
    `DELETE FROM taxi_captain_profile
     WHERE user_id = ANY($1::bigint[])`,
    [userIds]
  );
  await q(
    `DELETE FROM taxi_captain_subscription
     WHERE captain_user_id = ANY($1::bigint[])`,
    [userIds]
  );
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
}

test("taxi captain ride credit gates requests and decrements on completed rides", async () => {
  const userIds = [];
  try {
    const customer = await createActor("user");
    const captain = await createActor("taxi_captain");
    userIds.push(Number(customer.id), Number(captain.id));
    await makeCaptainReady(captain.id);

    const emptySubscription = await taxiService.getCaptainSubscriptionStatus(captain.id);
    assert.equal(emptySubscription.subscription.rideCredit.remainingRides, 0);
    assert.equal(emptySubscription.subscription.canAccess, false);

    await assert.rejects(
      () => taxiService.listNearbyRequestsForCaptain(captain.id, { radiusM: 15000 }),
      /DELIVERY_SUBSCRIPTION_EXPIRED|TAXI_CAPTAIN_RIDE_CREDIT_EMPTY/
    );

    await taxiRepo.addCaptainRideCreditTopUp({
      captainUserId: captain.id,
      ridesToAdd: 30,
      amountIqd: 20000,
      adminUserId: null,
      paymentMethod: "cash",
    });

    const charged = await taxiService.getCaptainSubscriptionStatus(captain.id);
    assert.equal(charged.subscription.rideCredit.remainingRides, 30);
    assert.equal(charged.subscription.canAccess, true);

    const created = await taxiService.createRideRequest(customer.id, {
      pickupLatitude: 33.19302,
      pickupLongitude: 44.62071,
      dropoffLatitude: 33.205,
      dropoffLongitude: 44.61,
      pickupLabel: "Bismayah pickup",
      dropoffLabel: "Bismayah dropoff",
      proposedFareIqd: 7000,
      searchRadiusM: 15000,
    });
    const rideId = Number(created.ride.id);
    const accepted = await taxiService.acceptRideByCaptain({
      captainUserId: captain.id,
      rideId,
    });
    assert.equal(accepted.ride.status, "captain_assigned");

    await taxiService.startRide({ captainUserId: captain.id, rideId });
    await taxiService.completeRide({ captainUserId: captain.id, rideId });
    await taxiService.completeRide({ captainUserId: captain.id, rideId }).catch(() => null);

    const afterComplete = await taxiService.getCaptainSubscriptionStatus(captain.id);
    assert.equal(afterComplete.subscription.rideCredit.remainingRides, 29);
  } finally {
    await cleanup(userIds);
  }
});
