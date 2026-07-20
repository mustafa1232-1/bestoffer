import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import * as taxiRepo from "../modules/taxi/taxi.repo.js";
import * as taxiService from "../modules/taxi/taxi.service.js";
import { hashPin } from "../shared/utils/hash.js";

function makeSuffix(prefix = "") {
  return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

const phoneSalt = Math.floor(Math.random() * 1_000_000);

function makePhone(seed = 0) {
  const tail = String(Date.now() + Number(seed || 0) + phoneSalt).slice(-9);
  return `07${tail}`;
}

async function createTaxiUser({
  fullName,
  phone,
  role,
  block = "A",
  buildingNumber = "101",
  apartment = "1",
}) {
  const pinHash = await hashPin("1234");
  return createUser({
    fullName,
    username: makeSuffix("user_").slice(0, 32),
    phone,
    pinHash,
    block,
    buildingNumber,
    apartment,
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "taxi_negotiation_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function seedCaptainReady(captainUserId, index) {
  await q(
    `UPDATE app_user
     SET delivery_account_approved = TRUE
     WHERE id = $1`,
    [Number(captainUserId)]
  );
  await q(
    `INSERT INTO taxi_captain_profile
      (
        user_id,
        vehicle_type,
        car_make,
        car_model,
        car_year,
        car_color,
        plate_number,
        is_active,
        rating_avg,
        rides_count
      )
     VALUES ($1, 'sedan', 'Toyota', 'Corolla', 2022, 'Silver', $2, TRUE, 4.8, 12)
     ON CONFLICT (user_id)
     DO UPDATE SET
       vehicle_type = EXCLUDED.vehicle_type,
       car_make = EXCLUDED.car_make,
       car_model = EXCLUDED.car_model,
       car_year = EXCLUDED.car_year,
       car_color = EXCLUDED.car_color,
       plate_number = EXCLUDED.plate_number,
       is_active = TRUE,
       rating_avg = EXCLUDED.rating_avg,
       rides_count = EXCLUDED.rides_count,
       updated_at = NOW()`,
    [Number(captainUserId), `TX-${String(index + 1).padStart(3, "0")}`]
  );

  await taxiRepo.upsertCaptainPresence({
    captainUserId,
    isOnline: true,
    latitude: 33.31456,
    longitude: 44.36611,
    headingDeg: 90,
    speedKmh: 0,
    accuracyM: 6,
    radiusM: 15000,
  });
}

async function cleanupRows({ userIds = [], rideIds = [] }) {
  const cleanUserIds = userIds
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value > 0);
  const cleanRideIds = rideIds
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value > 0);

  if (cleanRideIds.length > 0) {
    await q(
      `DELETE FROM app_notification
       WHERE COALESCE(payload->>'rideId', '') = ANY($1::text[])`,
      [cleanRideIds.map((value) => String(value))]
    );
    await q(
      `DELETE FROM taxi_ride_chat_message
       WHERE ride_request_id = ANY($1::bigint[])`,
      [cleanRideIds]
    );
    await q(
      `DELETE FROM taxi_ride_decline
       WHERE ride_request_id = ANY($1::bigint[])`,
      [cleanRideIds]
    );
    await q(
      `DELETE FROM taxi_ride_event
       WHERE ride_request_id = ANY($1::bigint[])`,
      [cleanRideIds]
    );
    await q(
      `DELETE FROM taxi_ride_location_log
       WHERE ride_request_id = ANY($1::bigint[])`,
      [cleanRideIds]
    );
    await q(
      `DELETE FROM taxi_ride_bid
       WHERE ride_request_id = ANY($1::bigint[])`,
      [cleanRideIds]
    );
    await q(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [
      cleanRideIds,
    ]);
  }

  if (cleanUserIds.length > 0) {
    await q(
      `DELETE FROM taxi_captain_presence
       WHERE captain_user_id = ANY($1::bigint[])`,
      [cleanUserIds]
    );
    await q(
      `DELETE FROM taxi_captain_profile
       WHERE user_id = ANY($1::bigint[])`,
      [cleanUserIds]
    );
    await q(
      `DELETE FROM taxi_captain_subscription
       WHERE captain_user_id = ANY($1::bigint[])`,
      [cleanUserIds]
    );
    await q(
      `DELETE FROM user_session
       WHERE user_id = ANY($1::bigint[])`,
      [cleanUserIds]
    );
    await q(
      `DELETE FROM app_notification
       WHERE user_id = ANY($1::bigint[])`,
      [cleanUserIds]
    );
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [cleanUserIds]);
  }
}

async function seedRequestRide(customerUserId, rideLabel) {
  const result = await taxiService.createRideRequest(customerUserId, {
    pickupLatitude: 33.31456,
    pickupLongitude: 44.36611,
    dropoffLatitude: 33.32091,
    dropoffLongitude: 44.39118,
    pickupLabel: `${rideLabel} pickup`,
    dropoffLabel: `${rideLabel} dropoff`,
    proposedFareIqd: 15000,
    searchRadiusM: 15000,
    note: `${rideLabel}-note`,
  });
  const ride = result?.ride || result;
  const rideId = Number(ride?.id || 0);
  assert.ok(rideId > 0, `${rideLabel} ride id missing`);
  return { ride, rideId };
}

test("taxi negotiation direct captain acceptance assigns one captain and blocks the rest", async () => {
  const state = {
    userIds: [],
    rideIds: [],
  };

  try {
    const customer = await createTaxiUser({
      fullName: `Taxi Negotiation Customer ${makeSuffix("cust-")}`,
      phone: makePhone(10),
      role: "user",
    });
    state.userIds.push(Number(customer.id));

    const captains = await Promise.all(
      [1, 2, 3, 4, 5].map(async (index) => {
        const captain = await createTaxiUser({
          fullName: `Taxi Captain ${index} ${makeSuffix("cap-")}`,
          phone: makePhone(20 + index),
          role: "taxi_captain",
        });
        state.userIds.push(Number(captain.id));
        await seedCaptainReady(captain.id, index);
        return captain;
      })
    );

    const directRide = await seedRequestRide(customer.id, "direct-accept");
    state.rideIds.push(directRide.rideId);

    const [winnerResult, loserResult] = await Promise.allSettled([
      taxiService.acceptRideByCaptain({
        captainUserId: captains[0].id,
        rideId: directRide.rideId,
      }),
      taxiService.acceptRideByCaptain({
        captainUserId: captains[1].id,
        rideId: directRide.rideId,
      }),
    ]);

    const winners = [winnerResult, loserResult].filter((entry) => entry.status === "fulfilled");
    const failures = [winnerResult, loserResult].filter((entry) => entry.status === "rejected");
    assert.equal(winners.length, 1, "exactly one captain should win the direct accept race");
    assert.equal(failures.length, 1, "exactly one captain should lose the direct accept race");

    const winningRide = winners[0].value.ride || winners[0].value;
    const winningCaptainId = Number(
      winningRide.assignedCaptainUserId ||
        winningRide.assigned_captain_user_id ||
        winningRide.captainUserId ||
        0
    );
    assert.ok(
      [Number(captains[0].id), Number(captains[1].id)].includes(
        Number(winningCaptainId)
      ),
      "winning captain should be one of the racing captains"
    );

    const losingError = failures[0].reason;
    assert.equal(losingError?.status, 409);
    assert.ok(
      ["TAXI_ALREADY_ASSIGNED", "TAXI_CAPTAIN_NOT_AVAILABLE"].includes(
        String(losingError?.message || "")
      ),
      `unexpected losing error: ${losingError?.message || losingError}`
    );

    const customerCurrentRide = await taxiService.getCurrentRideForCustomer(customer.id);
    const customerCurrentRidePayload =
      customerCurrentRide?.ride || customerCurrentRide;
    assert.ok(customerCurrentRidePayload, "customer current ride missing");
    assert.equal(
      Number(
        customerCurrentRidePayload.assignedCaptainUserId ||
          customerCurrentRidePayload.assigned_captain_user_id ||
          0
      ),
      Number(winningCaptainId)
    );
    assert.equal(customerCurrentRidePayload.status, "captain_assigned");

    const customerAssignedNotification = await q(
      `SELECT payload
       FROM app_notification
       WHERE user_id = $1
         AND type = 'taxi.ride.assigned'
         AND payload->>'rideId' = $2
       ORDER BY id DESC
       LIMIT 1`,
      [Number(customer.id), String(directRide.rideId)]
    );
    assert.equal(customerAssignedNotification.rowCount, 1);
    assert.equal(
      String(customerAssignedNotification.rows[0].payload?.target || ""),
      "taxi_ride_assigned"
    );

    const busyNearbyRequests = await taxiService.listNearbyRequestsForCaptain(
      winningCaptainId,
      {
        radiusM: 15000,
        limit: 10,
      }
    );
    assert.equal(busyNearbyRequests.total, 0);
    assert.deepEqual(busyNearbyRequests.items, []);

    const busyCaptainCurrentRide = await taxiService.getCurrentRideForCaptain(winningCaptainId);
    const busyCaptainCurrentRidePayload =
      busyCaptainCurrentRide?.ride || busyCaptainCurrentRide;
    assert.ok(
      busyCaptainCurrentRidePayload,
      "winning captain current ride missing"
    );
    assert.equal(
      Number(
        busyCaptainCurrentRidePayload.assignedCaptainUserId ||
          busyCaptainCurrentRidePayload.assigned_captain_user_id ||
          0
      ),
      Number(winningCaptainId)
    );
  } finally {
    await cleanupRows({
      userIds: state.userIds,
      rideIds: state.rideIds,
    });
  }
});

test("taxi negotiation keeps multi-offer rides separate from captain availability", async () => {
  const state = {
    userIds: [],
    rideIds: [],
  };

  try {
    const customer = await createTaxiUser({
      fullName: `Taxi Negotiation Customer ${makeSuffix("cust2-")}`,
      phone: makePhone(40),
      role: "user",
    });
    state.userIds.push(Number(customer.id));

    const captain = await createTaxiUser({
      fullName: `Taxi Busy Captain ${makeSuffix("cap-busy-")}`,
      phone: makePhone(41),
      role: "taxi_captain",
    });
    state.userIds.push(Number(captain.id));
    await seedCaptainReady(captain.id, 0);

    const ride = await seedRequestRide(customer.id, "busy-check");
    state.rideIds.push(ride.rideId);

    const accepted = await taxiService.acceptRideByCaptain({
      captainUserId: captain.id,
      rideId: ride.rideId,
    });
    assert.equal(accepted.ride.status, "captain_assigned");

    const nearby = await taxiService.listNearbyRequestsForCaptain(captain.id, {
      radiusM: 15000,
      limit: 10,
    });
    assert.equal(nearby.total, 0);
    assert.equal(nearby.items.length, 0);
  } finally {
    await cleanupRows({
      userIds: state.userIds,
      rideIds: state.rideIds,
    });
  }
});

test("taxi negotiation counteroffers one bid, atomically rejects losing offers, and releases captain after completion", async () => {
  const state = {
    userIds: [],
    rideIds: [],
  };

  try {
    const customer = await createTaxiUser({
      fullName: `Taxi Multi Bid Customer ${makeSuffix("cust-multi-")}`,
      phone: makePhone(70),
      role: "user",
    });
    state.userIds.push(Number(customer.id));

    const captainA = await createTaxiUser({
      fullName: `Taxi Multi Bid Captain A ${makeSuffix("cap-a-")}`,
      phone: makePhone(71),
      role: "taxi_captain",
    });
    state.userIds.push(Number(captainA.id));
    await seedCaptainReady(captainA.id, 0);

    const captainB = await createTaxiUser({
      fullName: `Taxi Multi Bid Captain B ${makeSuffix("cap-b-")}`,
      phone: makePhone(72),
      role: "taxi_captain",
    });
    state.userIds.push(Number(captainB.id));
    await seedCaptainReady(captainB.id, 1);

    const ride = await seedRequestRide(customer.id, "multi-bid");
    state.rideIds.push(ride.rideId);

    const bidA = await taxiService.submitBid({
      captainUserId: captainA.id,
      rideId: ride.rideId,
      dto: {
        offeredFareIqd: 17000,
        etaMinutes: 8,
        note: "captain-a-first-offer",
      },
    });
    const bidB = await taxiService.submitBid({
      captainUserId: captainB.id,
      rideId: ride.rideId,
      dto: {
        offeredFareIqd: 16500,
        etaMinutes: 10,
        note: "captain-b-waiting-offer",
      },
    });

    const bidAId = Number(bidA.bid.id);
    const bidBId = Number(bidB.bid.id);
    assert.notEqual(bidAId, bidBId);

    const customerRideWithOffers = await taxiService.getCurrentRideForCustomer(
      customer.id
    );
    const offerIds = new Set(
      customerRideWithOffers.offers.map((offer) => Number(offer.offerId))
    );
    assert.equal(customerRideWithOffers.offers.length, 2);
    assert.ok(offerIds.has(bidAId));
    assert.ok(offerIds.has(bidBId));

    const counter = await taxiService.counterOfferCurrentBid({
      customerUserId: customer.id,
      rideId: ride.rideId,
      bidId: bidAId,
      dto: {
        offeredFareIqd: 15500,
        note: "customer-targeted-counter",
      },
    });
    assert.equal(counter.ride.status, "searching");
    assert.equal(Number(counter.currentOfferId), bidAId);
    assert.equal(
      Number(counter.offers.find((offer) => Number(offer.offerId) === bidAId)?.offeredFareIqd),
      15500
    );
    assert.equal(
      counter.offers.find((offer) => Number(offer.offerId) === bidBId)?.status,
      "active"
    );

    const accepted = await taxiService.acceptBid({
      customerUserId: customer.id,
      rideId: ride.rideId,
      bidId: bidAId,
    });
    assert.equal(accepted.ride.status, "captain_assigned");
    assert.equal(Number(accepted.ride.assignedCaptainUserId), Number(captainA.id));
    assert.equal(Number(accepted.ride.agreedFareIqd), 15500);

    const firstRideBids = await taxiRepo.listRideBids(ride.rideId);
    assert.equal(
      firstRideBids.find((bid) => Number(bid.id) === bidAId)?.status,
      "accepted"
    );
    assert.equal(
      firstRideBids.find((bid) => Number(bid.id) === bidBId)?.status,
      "rejected"
    );

    await assert.rejects(
      () =>
        taxiService.acceptBid({
          customerUserId: customer.id,
          rideId: ride.rideId,
          bidId: bidBId,
        }),
      (error) => {
        assert.equal(error?.status, 409);
        assert.equal(error?.message, "TAXI_RIDE_NOT_ACCEPTING_BIDS");
        return true;
      }
    );

    await taxiService.startRide({
      captainUserId: captainA.id,
      rideId: ride.rideId,
    });
    const completed = await taxiService.completeRide({
      captainUserId: captainA.id,
      rideId: ride.rideId,
    });
    assert.equal(completed.status, "completed");

    const captainCurrentRide = await taxiService.getCurrentRideForCaptain(captainA.id);
    assert.equal(captainCurrentRide, null);

    const secondRide = await seedRequestRide(customer.id, "multi-bid-second");
    state.rideIds.push(secondRide.rideId);

    const secondBid = await taxiService.submitBid({
      captainUserId: captainA.id,
      rideId: secondRide.rideId,
      dto: {
        offeredFareIqd: 18000,
        etaMinutes: 6,
        note: "released-captain-second-offer",
      },
    });

    assert.equal(Number(secondBid.bid.captainUserId), Number(captainA.id));
    assert.equal(secondBid.bid.status, "active");
  } finally {
    await cleanupRows({
      userIds: state.userIds,
      rideIds: state.rideIds,
    });
  }
});

test("taxi request notifications skip captains that already have an active ride", async () => {
  const state = {
    userIds: [],
    rideIds: [],
  };

  try {
    const customerA = await createTaxiUser({
      fullName: `Taxi Notify Customer A ${makeSuffix("cust-a-")}`,
      phone: makePhone(60),
      role: "user",
    });
    state.userIds.push(Number(customerA.id));

    const customerB = await createTaxiUser({
      fullName: `Taxi Notify Customer B ${makeSuffix("cust-b-")}`,
      phone: makePhone(61),
      role: "user",
    });
    state.userIds.push(Number(customerB.id));

    const busyCaptain = await createTaxiUser({
      fullName: `Taxi Busy Notify Captain ${makeSuffix("cap-busy-notify-")}`,
      phone: makePhone(62),
      role: "taxi_captain",
    });
    state.userIds.push(Number(busyCaptain.id));
    await seedCaptainReady(busyCaptain.id, 0);

    const freeCaptain = await createTaxiUser({
      fullName: `Taxi Free Notify Captain ${makeSuffix("cap-free-notify-")}`,
      phone: makePhone(63),
      role: "taxi_captain",
    });
    state.userIds.push(Number(freeCaptain.id));
    await seedCaptainReady(freeCaptain.id, 1);

    const busyRide = await seedRequestRide(customerA.id, "busy-notify");
    state.rideIds.push(busyRide.rideId);
    await taxiService.acceptRideByCaptain({
      captainUserId: busyCaptain.id,
      rideId: busyRide.rideId,
    });

    const notifiedRide = await seedRequestRide(customerB.id, "notify-check");
    state.rideIds.push(notifiedRide.rideId);

    await new Promise((resolve) => setTimeout(resolve, 50));

    const busyNotificationCount = await q(
      `SELECT COUNT(*)::int AS count
       FROM app_notification
       WHERE user_id = $1
         AND type = 'taxi.ride.requested'
         AND payload->>'rideId' = $2`,
      [Number(busyCaptain.id), String(notifiedRide.rideId)]
    );
    const freeNotificationCount = await q(
      `SELECT COUNT(*)::int AS count
       FROM app_notification
       WHERE user_id = $1
         AND type = 'taxi.ride.requested'
         AND payload->>'rideId' = $2`,
      [Number(freeCaptain.id), String(notifiedRide.rideId)]
    );

    assert.equal(busyNotificationCount.rows[0].count, 0);
    assert.equal(freeNotificationCount.rows[0].count, 1);
  } finally {
    await cleanupRows({
      userIds: state.userIds,
      rideIds: state.rideIds,
    });
  }
});

test("taxi negotiation reject current bid returns a stable ride envelope", async () => {
  const state = {
    userIds: [],
    rideIds: [],
  };

  try {
    const customer = await createTaxiUser({
      fullName: `Taxi Reject Current Customer ${makeSuffix("cust-reject-")}`,
      phone: makePhone(50),
      role: "user",
    });
    state.userIds.push(Number(customer.id));

    const captain = await createTaxiUser({
      fullName: `Taxi Reject Current Captain ${makeSuffix("cap-reject-")}`,
      phone: makePhone(51),
      role: "taxi_captain",
    });
    state.userIds.push(Number(captain.id));
    await seedCaptainReady(captain.id, 0);

    const ride = await seedRequestRide(customer.id, "reject-current");
    state.rideIds.push(ride.rideId);

    await taxiService.submitBid({
      captainUserId: captain.id,
      rideId: ride.rideId,
      dto: {
        offeredFareIqd: 16000,
        etaMinutes: 7,
        note: "reject-current-bid",
      },
    });

    const result = await taxiService.rejectCurrentBid({
      customerUserId: customer.id,
      rideId: ride.rideId,
    });

    const returnedRide = result?.ride || result;
    assert.ok(returnedRide, "rejectCurrentBid should return a ride payload");
    assert.equal(Number(returnedRide.id || returnedRide.rideId || 0), ride.rideId);
    assert.ok(result.assignment, "rejectCurrentBid should include assignment data");
    assert.equal(Number(result.assignment.rideId || 0), ride.rideId);
  } finally {
    await cleanupRows({
      userIds: state.userIds,
      rideIds: state.rideIds,
    });
  }
});
