/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { app } from "../app.js";
import { ensureSchema, pool } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  cleanupAdminArtifacts,
  createActor,
  ensureSuperAdminAccount,
  expectNotification,
  readId,
  request,
  startLocalServer,
  stopLocalServer,
} from "./e2eTestUtils.js";

function extractRideBundle(payload) {
  if (payload?.ride?.ride) return payload.ride;
  if (payload?.ride && typeof payload.ride === "object") return payload;
  return payload;
}

function shouldSkipMigrations() {
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

function extractRide(payload) {
  const bundle = extractRideBundle(payload);
  if (bundle?.ride?.id) return bundle.ride;
  if (bundle?.id) return bundle;
  return null;
}

function rideStatus(payload) {
  return String(extractRide(payload)?.status || "");
}

function findBid(bundle) {
  const source = extractRideBundle(bundle);
  const bids = Array.isArray(source?.bids) ? source.bids : [];
  return bids[0] || null;
}

function normalizeRelationPair(a, b) {
  const x = Number(a);
  const y = Number(b);
  return x < y ? { userAId: x, userBId: y } : { userAId: y, userBId: x };
}

async function fetchUserRole(userId) {
  const result = await pool.query(
    `SELECT role
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return String(result.rows[0]?.role || "");
}

async function expectRidePriceRaiseRecommended(
  baseUrl,
  actor,
  expectedRideId,
  label
) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const response = await request(baseUrl, actor, "GET", "/api/taxi/rides/current");
    assertStatus(response, 200, label);
    const ride = extractRide(response.data);
    if (
      Number(ride?.id || 0) === Number(expectedRideId) &&
      ride?.priceRaiseRecommended === true
    ) {
      return ride;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  throw new Error(`${label} -> price raise recommendation not observed`);
}

async function cleanup(state) {
  const userIds = [
    state.customerUserId,
    ...(state.captainUserIds || []),
    state.friendUserId,
  ].filter(
    (value) => Number.isFinite(Number(value)) && Number(value) > 0
  );
  const rideIds = (state.rideIds || []).filter(
    (value) => Number.isFinite(Number(value)) && Number(value) > 0
  );

  await cleanupAdminArtifacts({
    adminSessionId: state.adminSessionId,
    superAdminId: state.superAdminId,
    runTag: state.runTag,
    approvalPaths: (state.captainUserIds || []).map(
      (captainUserId) => `/api/admin/taxi-captains/${captainUserId}/approve`
    ),
  });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    if (state.superAdminId && (state.captainUserIds || []).length > 0) {
      await client.query(
        `DELETE FROM app_notification
         WHERE user_id = $1
           AND type = 'admin_delivery_pending_approval'
           AND COALESCE(payload->>'captainUserId', '') = ANY($2::text[])`,
        [
          Number(state.superAdminId),
          state.captainUserIds.map((value) => String(value)),
        ]
      );
    }

    if (rideIds.length > 0) {
      await client.query(
        `DELETE FROM app_notification
         WHERE COALESCE(payload->>'rideId', '') = ANY($1::text[])`,
        [rideIds.map((value) => String(value))]
      );
      await client.query(
        `DELETE FROM taxi_ride_decline
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_chat_message
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_friend_share
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_location_log
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_event
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_bid
         WHERE ride_request_id = ANY($1::bigint[])`,
        [rideIds]
      );
      await client.query(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [
        rideIds,
      ]);
    }

    if ((state.captainUserIds || []).length > 0) {
      await client.query(
        `DELETE FROM taxi_captain_profile_edit_request
         WHERE captain_user_id = ANY($1::bigint[])`,
        [state.captainUserIds]
      );
      await client.query(
        `DELETE FROM taxi_captain_subscription
         WHERE captain_user_id = ANY($1::bigint[])`,
        [state.captainUserIds]
      );
      await client.query(
        `DELETE FROM taxi_captain_presence
         WHERE captain_user_id = ANY($1::bigint[])`,
        [state.captainUserIds]
      );
      await client.query(
        `DELETE FROM taxi_captain_profile
         WHERE user_id = ANY($1::bigint[])`,
        [state.captainUserIds]
      );
    }

    if (userIds.length > 0) {
      if (state.customerUserId && state.friendUserId) {
        const pair = normalizeRelationPair(state.customerUserId, state.friendUserId);
        await client.query(
          `DELETE FROM social_user_relation
           WHERE user_a_id = $1
             AND user_b_id = $2`,
          [pair.userAId, pair.userBId]
        );
      }
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM app_notification
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM customer_address
         WHERE customer_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_push_token
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM user_session
         WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [
        userIds,
      ]);
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function expectCurrentRide(baseUrl, actor, path, expectedStatus, label) {
  const response = await request(baseUrl, actor, "GET", path);
  assertStatus(response, 200, label);
  assert.equal(
    rideStatus(response.data),
    expectedStatus,
    `${label} -> expected ${expectedStatus}, got ${rideStatus(response.data)}`
  );
  return response.data;
}

async function expectNoCurrentRide(baseUrl, actor, path, label) {
  const response = await request(baseUrl, actor, "GET", path);
  assertStatus(response, 200, label);
  assert.equal(response.data?.ride, null, `${label} -> expected null ride`);
}

async function main() {
  validateRuntimeEnv();
  if (!shouldSkipMigrations()) {
    await runSqlMigrations({ force: true });
  }
  if (!shouldSkipEnsureSchema()) {
    await ensureSchema();
  }

  const runTag = buildRunTag("taxi-e2e");
  const timestampSeed = Number(String(Date.now()).slice(-8));
  const state = {
    runTag,
    customerPhone: buildPhone("079", timestampSeed),
    friendPhone: buildPhone("077", timestampSeed + 2),
    captainPhones: [
      buildPhone("078", timestampSeed + 11),
      buildPhone("078", timestampSeed + 12),
      buildPhone("078", timestampSeed + 13),
    ],
    superAdminId: await ensureSuperAdminAccount(),
    customerUserId: null,
    captainUserIds: [],
    friendUserId: null,
    rideIds: [],
    adminSessionId: null,
  };

  const coords = {
    pickup: { latitude: 33.31456, longitude: 44.36611 },
    dropoff: { latitude: 33.32091, longitude: 44.39118 },
    enRoute: { latitude: 33.31641, longitude: 44.37172 },
    started: { latitude: 33.31852, longitude: 44.37961 },
  };

  let server = null;

  try {
    const started = await startLocalServer(app);
    server = started.server;
    const baseUrl = started.baseUrl;
    console.log(`[taxi-e2e] baseUrl=${baseUrl} runTag=${runTag}`);

    const admin = createActor("admin", runTag, "e2e-taxi-check/1");
    const customer = createActor("customer", runTag, "e2e-taxi-check/1");
    const friend = createActor("friend", runTag, "e2e-taxi-check/1");
    const captains = state.captainPhones.map((phone, index) => ({
      actor: createActor(`captain-${index + 1}`, runTag, "e2e-taxi-check/1"),
      phone,
      fullName: `Taxi Captain ${index + 1} ${runTag}`,
      plateNumber: `TX${String(timestampSeed + index).slice(-5)}`,
      userId: null,
    }));

    const customerRegister = await request(
      baseUrl,
      customer,
      "POST",
      "/api/auth/register",
      {
        fullName: `Taxi Customer ${runTag}`,
        phone: state.customerPhone,
        pin: "1234",
        block: "A1",
        buildingNumber: "A101",
        apartment: "101",
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "analytics_v1",
      }
    );
    assertStatus(customerRegister, 201, "customer register");
    customer.token = String(customerRegister.data?.token || "");
    customer.sessionId = Number(customerRegister.data?.sessionId || 0) || null;
    state.customerUserId = readId(customerRegister.data?.user);

    const friendRegister = await request(
      baseUrl,
      friend,
      "POST",
      "/api/auth/register",
      {
        fullName: `Taxi Friend ${runTag}`,
        phone: state.friendPhone,
        pin: "1234",
        block: "A2",
        buildingNumber: "A201",
        apartment: "202",
        analyticsConsentAccepted: true,
        analyticsConsentVersion: "analytics_v1",
      }
    );
    assertStatus(friendRegister, 201, "friend register");
    friend.token = String(friendRegister.data?.token || "");
    friend.sessionId = Number(friendRegister.data?.sessionId || 0) || null;
    state.friendUserId = readId(friendRegister.data?.user);

    for (const [index, captainCtx] of captains.entries()) {
      const captainRegister = await request(
        baseUrl,
        captainCtx.actor,
        "POST",
        "/api/taxi/captain/register",
        {
          fullName: captainCtx.fullName,
          phone: captainCtx.phone,
          pin: "1234",
          block: "B1",
          buildingNumber: `B10${index + 1}`,
          apartment: `10${index + 1}`,
          carMake: "Toyota",
          carModel: "Corolla",
          vehicleType: "car",
          plateNumber: captainCtx.plateNumber,
          carYear: 2021,
          carColor: "Silver",
          analyticsConsentAccepted: true,
          analyticsConsentVersion: "analytics_v1",
        }
      );
      assertStatus(captainRegister, 201, `captain ${index + 1} register`);
      captainCtx.userId = readId(captainRegister.data?.user);
      assert.ok(captainCtx.userId, `captain ${index + 1} id missing`);
      state.captainUserIds.push(captainCtx.userId);
    }

    const adminLogin = await request(baseUrl, admin, "POST", "/api/auth/login", {
      phone: env.superAdminPhone,
      pin: env.superAdminPin,
    });
    assertStatus(adminLogin, 200, "admin login");
    admin.token = String(adminLogin.data?.token || "");
    admin.sessionId = Number(adminLogin.data?.sessionId || 0) || null;
    state.adminSessionId = admin.sessionId;

    await expectNotification(
      {
        userId: state.superAdminId,
        type: "admin_delivery_pending_approval",
        payloadChecks: { captainUserId: state.captainUserIds[0] },
      },
      "admin pending captain notification"
    );

    const pendingCaptains = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/taxi-captains/pending"
    );
    assertStatus(pendingCaptains, 200, "pending taxi captains");
    assert.ok(
      Array.isArray(pendingCaptains.data) &&
        state.captainUserIds.every((captainUserId) =>
          pendingCaptains.data.some(
            (item) => Number(item?.id || 0) === Number(captainUserId)
          )
        ),
      "pending taxi captains should include all created captains"
    );

    const pendingDeliveries = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/delivery/pending"
    );
    assertStatus(pendingDeliveries, 200, "pending app deliveries");
    assert.ok(
      Array.isArray(pendingDeliveries.data) &&
        state.captainUserIds.every(
          (captainUserId) =>
            !pendingDeliveries.data.some(
              (item) => Number(item?.id || 0) === Number(captainUserId)
            )
        ),
      "taxi captains must not leak into app delivery approvals"
    );

    for (const [index, captainCtx] of captains.entries()) {
      const approveCaptain = await request(
        baseUrl,
        admin,
        "PATCH",
        `/api/admin/taxi-captains/${captainCtx.userId}/approve`
      );
      assertStatus(approveCaptain, 200, `approve captain ${index + 1}`);

      const captainLogin = await request(
        baseUrl,
        captainCtx.actor,
        "POST",
        "/api/auth/login",
        {
          phone: captainCtx.phone,
          pin: "1234",
        }
      );
      assertStatus(captainLogin, 200, `captain ${index + 1} login`);
      captainCtx.actor.token = String(captainLogin.data?.token || "");
      captainCtx.actor.sessionId =
        Number(captainLogin.data?.sessionId || 0) || null;
      const role = await fetchUserRole(captainCtx.userId);
      assert.equal(role, "taxi_captain", `captain ${index + 1} role must be taxi_captain`);
    }

    const pendingCaptainsAfterApprove = await request(
      baseUrl,
      admin,
      "GET",
      "/api/admin/taxi-captains/pending"
    );
    assertStatus(pendingCaptainsAfterApprove, 200, "pending taxi captains after approve");
    assert.ok(
      Array.isArray(pendingCaptainsAfterApprove.data) &&
        state.captainUserIds.every(
          (captainUserId) =>
            !pendingCaptainsAfterApprove.data.some(
              (item) => Number(item?.id || 0) === Number(captainUserId)
            )
        ),
      "approved taxi captains should disappear from pending list"
    );

    const captainProfile = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/profile"
    );
    assertStatus(captainProfile, 200, "captain profile");
    assert.equal(captainProfile.data?.profile?.carMake, "Toyota");

    const captainSubscription = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/subscription"
    );
    assertStatus(captainSubscription, 200, "captain subscription");
    assert.equal(captainSubscription.data?.subscription?.canAccess, true);

    if (state.customerUserId && state.friendUserId) {
      const pair = normalizeRelationPair(state.customerUserId, state.friendUserId);
      const relationInsert = await pool.query(
        `INSERT INTO social_user_relation
          (
            user_a_id,
            user_b_id,
            initiator_user_id,
            status,
            requested_at,
            responded_at,
            updated_at
          )
         VALUES ($1, $2, $3, 'accepted', NOW(), NOW(), NOW())
         ON CONFLICT (user_a_id, user_b_id)
         DO UPDATE SET
           initiator_user_id = EXCLUDED.initiator_user_id,
           status = 'accepted',
           requested_at = NOW(),
           responded_at = NOW(),
           updated_at = NOW()`,
        [pair.userAId, pair.userBId, Number(state.customerUserId)]
      );
      assert.ok(relationInsert.rowCount >= 0, "friend relation should be ready");
    }

    await expectNoCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "customer current ride initially"
    );
    await expectNoCurrentRide(
      baseUrl,
      captains[0].actor,
      "/api/taxi/captain/current-ride",
      "captain one current ride initially"
    );

    const nearbyBeforeRide = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/nearby-requests?radiusM=4000&limit=10"
    );
    assertStatus(nearbyBeforeRide, 200, "nearby requests before ride");
    assert.equal(nearbyBeforeRide.data?.items?.length || 0, 0);

    for (const [index, captainCtx] of captains.entries()) {
      const captainPresence = await request(
        baseUrl,
        captainCtx.actor,
        "POST",
        "/api/taxi/captain/presence",
        {
          isOnline: true,
          latitude: coords.pickup.latitude,
          longitude: coords.pickup.longitude,
          headingDeg: 90,
          speedKmh: 0,
          accuracyM: 6,
          radiusM: 4000,
        }
      );
      assertStatus(captainPresence, 200, `captain ${index + 1} presence`);
    }

    const rejectedRideCreate = await request(baseUrl, customer, "POST", "/api/taxi/rides", {
      pickupLatitude: coords.pickup.latitude,
      pickupLongitude: coords.pickup.longitude,
      dropoffLatitude: coords.dropoff.latitude,
      dropoffLongitude: coords.dropoff.longitude,
      pickupLabel: `Rejected taxi pickup ${runTag}`,
      dropoffLabel: `Rejected taxi dropoff ${runTag}`,
      proposedFareIqd: 12000,
      searchRadiusM: 3000,
      note: `ride-rejects-${runTag}`,
    });
    assertStatus(rejectedRideCreate, 201, "create ride for rejection threshold");
    const rejectedRideId = readId(rejectedRideCreate.data?.ride);
    assert.ok(rejectedRideId, "rejected ride id missing");
    state.rideIds.push(rejectedRideId);

    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.ride.requested",
        payloadChecks: { rideId: rejectedRideId },
      },
      "captain new ride notification"
    );

    for (const [index, captainCtx] of captains.entries()) {
      const nearbyRequests = await request(
        baseUrl,
        captainCtx.actor,
        "GET",
        "/api/taxi/captain/nearby-requests?radiusM=4000&limit=10"
      );
      assertStatus(nearbyRequests, 200, `nearby requests before decline ${index + 1}`);
      assert.ok(
        Array.isArray(nearbyRequests.data?.items) &&
          nearbyRequests.data.items.some(
            (item) => Number(item?.id || 0) === rejectedRideId
          ),
        `captain ${index + 1} should see rejected ride`
      );

      const declineRide = await request(
        baseUrl,
        captainCtx.actor,
        "POST",
        `/api/taxi/rides/${rejectedRideId}/decline`
      );
      assertStatus(declineRide, 200, `decline ride by captain ${index + 1}`);
      assert.equal(
        Number(declineRide.data?.rejectedCaptainsCount || 0),
        index + 1,
        `decline counter after captain ${index + 1}`
      );
    }

    const rideAfterRejects = await expectRidePriceRaiseRecommended(
      baseUrl,
      customer,
      rejectedRideId,
      "price raise after three distinct rejects"
    );
    assert.equal(
      Number(rideAfterRejects?.rejectedCaptainsCount || 0),
      3,
      "ride should expose three captain rejects"
    );
    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.ride.price_raise_recommended",
        payloadChecks: { rideId: rejectedRideId },
      },
      "price raise notification after three rejects"
    );

    const cancelRejectedRide = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${rejectedRideId}/cancel`
    );
    assertStatus(cancelRejectedRide, 200, "cancel rejected ride");
    await expectNoCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "customer current ride after reject-threshold cancellation"
    );

    const timeoutRideCreate = await request(baseUrl, customer, "POST", "/api/taxi/rides", {
      pickupLatitude: coords.pickup.latitude,
      pickupLongitude: coords.pickup.longitude,
      dropoffLatitude: coords.dropoff.latitude,
      dropoffLongitude: coords.dropoff.longitude,
      pickupLabel: `Timeout taxi pickup ${runTag}`,
      dropoffLabel: `Timeout taxi dropoff ${runTag}`,
      proposedFareIqd: 9000,
      searchRadiusM: 3000,
      note: `ride-timeout-${runTag}`,
    });
    assertStatus(timeoutRideCreate, 201, "create ride for timeout threshold");
    const timeoutRideId = readId(timeoutRideCreate.data?.ride);
    assert.ok(timeoutRideId, "timeout ride id missing");
    state.rideIds.push(timeoutRideId);

    await pool.query(
      `UPDATE taxi_ride_request
       SET final_acceptance_deadline_at = NOW() - INTERVAL '2 seconds'
       WHERE id = $1`,
      [Number(timeoutRideId)]
    );

    const rideAfterTimeout = await expectRidePriceRaiseRecommended(
      baseUrl,
      customer,
      timeoutRideId,
      "price raise after acceptance timeout"
    );
    assert.equal(
      rideAfterTimeout?.priceRaiseRecommended,
      true,
      "timeout ride should request price raise"
    );

    const cancelTimeoutRide = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${timeoutRideId}/cancel`
    );
    assertStatus(cancelTimeoutRide, 200, "cancel timeout ride");
    await expectNoCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "customer current ride after timeout cancellation"
    );

    const createRide = await request(baseUrl, customer, "POST", "/api/taxi/rides", {
      pickupLatitude: coords.pickup.latitude,
      pickupLongitude: coords.pickup.longitude,
      dropoffLatitude: coords.dropoff.latitude,
      dropoffLongitude: coords.dropoff.longitude,
      pickupLabel: `Taxi pickup ${runTag}`,
      dropoffLabel: `Taxi dropoff ${runTag}`,
      proposedFareIqd: 12000,
      searchRadiusM: 3000,
      note: `ride-note-${runTag}`,
    });
    assertStatus(createRide, 201, "create ride");
    const activeRideId = readId(createRide.data?.ride);
    assert.ok(activeRideId, "active ride id missing");
    state.rideIds.push(activeRideId);

    const happyNearbyRequests = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/nearby-requests?radiusM=4000&limit=10"
    );
    assertStatus(happyNearbyRequests, 200, "nearby requests for active ride");
    assert.ok(
      Array.isArray(happyNearbyRequests.data?.items) &&
        happyNearbyRequests.data.items.some(
          (item) => Number(item?.id || 0) === activeRideId
        ),
      "captain one should see active ride"
    );

    const firstBid = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/bids`,
      {
        offeredFareIqd: 13000,
        etaMinutes: 7,
        note: `initial-bid-${runTag}`,
      }
    );
    assertStatus(firstBid, 201, "captain initial bid");
    const activeBidId = readId(firstBid.data?.bid);
    assert.ok(activeBidId, "active bid id missing");

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.offer.received",
        payloadChecks: { rideId: activeRideId, bidId: activeBidId },
      },
      "customer bid submitted notification"
    );

    const counterOffer = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${activeRideId}/bids/current/counter`,
      {
        offeredFareIqd: 12500,
        note: `counter-offer-${runTag}`,
      }
    );
    assertStatus(counterOffer, 200, "customer counter offer");
    assert.equal(counterOffer.data?.negotiationClosed, false);

    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.counter_offer.received",
        payloadChecks: { rideId: activeRideId },
      },
      "captain counter offer notification"
    );

    const secondBid = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/bids`,
      {
        offeredFareIqd: 12800,
        etaMinutes: 6,
        note: `final-bid-${runTag}`,
      }
    );
    assertStatus(secondBid, 201, "captain final bid");

    const customerRideAfterBid = await expectCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "searching",
      "customer ride after bidding"
    );
    const customerRideAfterBidState = extractRide(customerRideAfterBid);
    assert.equal(
      Number(customerRideAfterBidState?.currentBidId || 0),
      activeBidId,
      "current bid id should remain the first captain bid"
    );

    const acceptBid = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${activeRideId}/bids/${activeBidId}/accept`
    );
    assertStatus(acceptBid, 200, "accept bid");
    assert.equal(rideStatus(acceptBid.data), "captain_assigned");

    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.offer.accepted",
        payloadChecks: { rideId: activeRideId, bidId: activeBidId },
      },
      "captain accepted bid notification"
    );

    await expectCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "captain_assigned",
      "customer ride after acceptance"
    );
    await expectCurrentRide(
      baseUrl,
      captains[0].actor,
      "/api/taxi/captain/current-ride",
      "captain_assigned",
      "captain ride after acceptance"
    );

    const customerChat = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${activeRideId}/chat`,
      {
        messageText: `chat-from-customer-${runTag}`,
      }
    );
    assertStatus(customerChat, 201, "customer chat");
    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.chat.message",
        payloadChecks: { rideId: activeRideId },
      },
      "captain chat notification"
    );

    const captainChat = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/chat`,
      {
        messageText: `chat-from-captain-${runTag}`,
      }
    );
    assertStatus(captainChat, 201, "captain chat");
    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.chat.message",
        payloadChecks: { rideId: activeRideId },
      },
      "customer chat notification"
    );

    const shareRide = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${activeRideId}/share/friends`,
      {
        friendUserIds: [state.friendUserId],
      }
    );
    assertStatus(shareRide, 200, "share ride with friend");
    assert.equal(Number(shareRide.data?.total || 0), 1);

    await expectNotification(
      {
        userId: state.friendUserId,
        type: "taxi.ride.shared",
        payloadChecks: { rideId: activeRideId },
      },
      "friend shared ride notification"
    );

    const sharedFriends = await request(
      baseUrl,
      customer,
      "GET",
      `/api/taxi/rides/${activeRideId}/share/friends`
    );
    assertStatus(sharedFriends, 200, "list ride shared friends");
    assert.ok(
      Array.isArray(sharedFriends.data?.items) &&
        sharedFriends.data.items.some(
          (item) => Number(item?.friendUserId || 0) === state.friendUserId
        ),
      "ride share list should include friend"
    );

    const firstLocation = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/location`,
      {
        latitude: coords.enRoute.latitude,
        longitude: coords.enRoute.longitude,
        headingDeg: 45,
        speedKmh: 35,
        accuracyM: 8,
      }
    );
    assertStatus(firstLocation, 200, "first location update");

    const friendTrack = await request(
      baseUrl,
      friend,
      "GET",
      `/api/taxi/rides/${activeRideId}/shared-track`
    );
    assertStatus(friendTrack, 200, "friend scoped track");
    assert.equal(Number(friendTrack.data?.ride?.id || 0), activeRideId);

    const arrive = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/arrive`
    );
    assertStatus(arrive, 200, "arrive");
    assert.equal(rideStatus(arrive.data), "captain_arriving");

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.captain.arrived",
        payloadChecks: { rideId: activeRideId },
      },
      "captain arriving notification"
    );

    const secondLocation = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/location`,
      {
        latitude: coords.started.latitude,
        longitude: coords.started.longitude,
        headingDeg: 60,
        speedKmh: 25,
        accuracyM: 8,
      }
    );
    assertStatus(secondLocation, 200, "second location update");

    const startRide = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/start`
    );
    assertStatus(startRide, 200, "start ride");
    assert.equal(rideStatus(startRide.data), "ride_started");

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.ride.started",
        payloadChecks: { rideId: activeRideId },
      },
      "ride started notification"
    );

    const completeRide = await request(
      baseUrl,
      captains[0].actor,
      "POST",
      `/api/taxi/rides/${activeRideId}/complete`
    );
    assertStatus(completeRide, 200, "complete ride");
    assert.equal(rideStatus(completeRide.data), "completed");

    await expectNotification(
      {
        userId: state.customerUserId,
        type: "taxi.ride.completed",
        payloadChecks: { rideId: activeRideId },
      },
      "ride completed notification"
    );
    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.ride.completed",
        payloadChecks: { rideId: activeRideId },
      },
      "captain completed notification"
    );

    await expectNoCurrentRide(
      baseUrl,
      customer,
      "/api/taxi/rides/current",
      "customer current ride after complete"
    );
    await expectNoCurrentRide(
      baseUrl,
      captains[0].actor,
      "/api/taxi/captain/current-ride",
      "captain current ride after complete"
    );

    const sharedTrackAfterComplete = await request(
      baseUrl,
      friend,
      "GET",
      `/api/taxi/rides/${activeRideId}/shared-track`
    );
    assertStatus(sharedTrackAfterComplete, 404, "shared track after ride completion");

    const rateRide = await request(
      baseUrl,
      customer,
      "POST",
      `/api/taxi/rides/${activeRideId}/rate`,
      {
        rating: 5,
        review: `great-ride-${runTag}`,
      }
    );
    assertStatus(rateRide, 200, "rate ride");
    assert.equal(Number(rateRide.data?.rating || 0), 5);

    await expectNotification(
      {
        userId: captains[0].userId,
        type: "taxi.ride.rated",
        payloadChecks: { rideId: activeRideId, rating: 5 },
      },
      "ride rated notification"
    );

    const captainDashboard = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/dashboard?period=day&limit=10"
    );
    assertStatus(captainDashboard, 200, "captain dashboard");
    assert.ok(Number(captainDashboard.data?.metrics?.day?.ridesCount || 0) >= 1);

    const captainHistory = await request(
      baseUrl,
      captains[0].actor,
      "GET",
      "/api/taxi/captain/history?period=month&limit=10"
    );
    assertStatus(captainHistory, 200, "captain history");
    assert.ok(
      Array.isArray(captainHistory.data?.items) &&
        captainHistory.data.items.some(
          (item) => Number(item?.id || 0) === activeRideId
        ),
      "captain history should include completed ride"
    );

    console.log(
      `[taxi-e2e] passed rejectedRideId=${rejectedRideId} timeoutRideId=${timeoutRideId} activeRideId=${activeRideId} captainUserIds=${state.captainUserIds.join(",")}`
    );
  } finally {
    try {
      await cleanup(state);
    } finally {
      await stopLocalServer(server);
      await pool.end();
    }
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[taxi-e2e] failed", error);
    process.exit(1);
  });
