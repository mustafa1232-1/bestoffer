import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import * as taxiRepo from "../modules/taxi/taxi.repo.js";
import { hashPin } from "../shared/utils/hash.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let phoneSeq = 0;
function makePhone() {
  phoneSeq += 1;
  const tail = String(Date.now() + phoneSeq + phoneSalt).slice(-9);
  return `07${tail}`;
}
function makeSuffix(prefix = "") {
  return `${prefix}${Date.now().toString(36)}${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

const createdUserIds = [];
const createdRideIds = [];

async function makeUser(role) {
  const pinHash = await hashPin("1234");
  const user = await createUser({
    fullName: `T ${role}`,
    username: makeSuffix("cxl_").slice(0, 32),
    phone: makePhone(),
    pinHash,
    block: "A",
    buildingNumber: "101",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "taxi_cancel_lock_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  createdUserIds.push(id);
  return id;
}

async function makeRide({ customerId, captainId = null, status }) {
  const r = await q(
    `INSERT INTO taxi_ride_request
       (customer_user_id, assigned_captain_user_id, pickup_latitude, pickup_longitude,
        dropoff_latitude, dropoff_longitude, pickup_label, dropoff_label,
        proposed_fare_iqd, status)
     VALUES ($1,$2,33.31,44.36,33.32,44.37,'P','D',10000,$3)
     RETURNING id`,
    [customerId, captainId, status]
  );
  const id = Number(r.rows[0].id);
  createdRideIds.push(id);
  return id;
}

async function rideRow(id) {
  const r = await q(`SELECT * FROM taxi_ride_request WHERE id = $1`, [id]);
  return r.rows[0];
}

test.after(async () => {
  if (createdRideIds.length) {
    await q(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [
      createdRideIds,
    ]);
  }
  if (createdUserIds.length) {
    await q(`DELETE FROM taxi_captain_profile WHERE user_id = ANY($1::bigint[])`, [
      createdUserIds,
    ]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [createdUserIds]);
  }
});

test("customer can cancel while captain_assigned, recording who/why/previous status", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  const rideId = await makeRide({ customerId, captainId, status: "captain_assigned" });

  const res = await taxiRepo.cancelRide({
    rideId,
    customerUserId: customerId,
    reasonCode: "changed_mind",
    reasonText: "no longer needed",
  });
  assert.equal(res.code, "OK");

  const row = await rideRow(rideId);
  assert.equal(row.status, "cancelled");
  assert.equal(row.cancelled_by_role, "customer");
  assert.equal(Number(row.cancelled_by_user_id), customerId);
  assert.equal(row.cancel_reason_code, "changed_mind");
  assert.equal(row.cancel_previous_status, "captain_assigned");
  assert.equal(row.cancel_is_emergency, false);
});

test("cancellation is locked for BOTH parties once the captain is en route", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");

  for (const lockedStatus of ["captain_arriving", "ride_started"]) {
    const rideId = await makeRide({ customerId, captainId, status: lockedStatus });

    const cust = await taxiRepo.cancelRide({
      rideId,
      customerUserId: customerId,
      reasonCode: "changed_mind",
    });
    assert.equal(cust.code, "TAXI_CANCELLATION_LOCKED", `customer @ ${lockedStatus}`);

    const cap = await taxiRepo.cancelRideByCaptain({
      rideId,
      captainUserId: captainId,
      reasonCode: "too_far",
    });
    assert.equal(cap.code, "TAXI_CANCELLATION_LOCKED", `captain @ ${lockedStatus}`);

    // ride is untouched by the rejected cancellations
    assert.equal((await rideRow(rideId)).status, lockedStatus);
  }
});

test("captain can cancel only a ride assigned to them, before heading out", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  const otherCaptainId = await makeUser("taxi_captain");

  const rideId = await makeRide({ customerId, captainId, status: "captain_assigned" });

  // a different captain cannot cancel it
  const wrong = await taxiRepo.cancelRideByCaptain({
    rideId,
    captainUserId: otherCaptainId,
    reasonCode: "too_far",
  });
  assert.equal(wrong.code, "RIDE_NOT_ASSIGNED_TO_CAPTAIN");

  // the assigned captain can
  const ok = await taxiRepo.cancelRideByCaptain({
    rideId,
    captainUserId: captainId,
    reasonCode: "too_far",
    reasonText: "distance too long",
  });
  assert.equal(ok.code, "OK");
  const row = await rideRow(rideId);
  assert.equal(row.cancelled_by_role, "captain");
  assert.equal(row.cancel_previous_status, "captain_assigned");
});

test("re-cancelling an already-cancelled ride is idempotent (no error, no duplicate)", async () => {
  const customerId = await makeUser("user");
  const rideId = await makeRide({ customerId, status: "searching" });

  const first = await taxiRepo.cancelRide({
    rideId,
    customerUserId: customerId,
    reasonCode: "changed_mind",
  });
  assert.equal(first.code, "OK");

  const second = await taxiRepo.cancelRide({
    rideId,
    customerUserId: customerId,
    reasonCode: "changed_mind",
  });
  assert.equal(second.code, "ALREADY_CANCELLED");
});

test("emergency: raising a ticket does NOT cancel the ride and is idempotent per reporter", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  const rideId = await makeRide({ customerId, captainId, status: "ride_started" });

  const em = await taxiRepo.createRideEmergency({
    rideId,
    reportedByUserId: customerId,
    reportedByRole: "customer",
    category: "safety",
    message: "need help",
  });
  assert.equal(em.code, "OK");
  assert.equal(em.alreadyOpen, false);
  assert.equal(em.emergency.status, "open");
  assert.equal(em.emergency.ride_status_at_report, "ride_started");

  // the ride keeps running — the emergency is an added ticket, not an auto-cancel
  assert.equal((await rideRow(rideId)).status, "ride_started");

  const again = await taxiRepo.createRideEmergency({
    rideId,
    reportedByUserId: customerId,
    reportedByRole: "customer",
  });
  assert.equal(again.alreadyOpen, true);
  assert.equal(Number(again.emergency.id), Number(em.emergency.id));
});

test("authorized emergency cancel closes the ride and resolves the open ticket with full trail", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  const adminId = await makeUser("admin");
  const rideId = await makeRide({ customerId, captainId, status: "captain_arriving" });

  const em = await taxiRepo.createRideEmergency({
    rideId,
    reportedByUserId: captainId,
    reportedByRole: "captain",
    category: "safety",
  });
  assert.equal(em.code, "OK");

  const cancel = await taxiRepo.adminEmergencyCancelRide({
    rideId,
    adminUserId: adminId,
    reasonText: "verified safety incident",
    secondApproverUserId: null,
  });
  assert.equal(cancel.code, "OK");

  const row = await rideRow(rideId);
  assert.equal(row.status, "cancelled");
  assert.equal(row.cancelled_by_role, "admin");
  assert.equal(Number(row.cancelled_by_user_id), adminId);
  assert.equal(row.cancel_is_emergency, true);
  assert.equal(row.cancel_previous_status, "captain_arriving");

  const emRow = await q(
    `SELECT * FROM taxi_ride_emergency WHERE id = $1`,
    [em.emergency.id]
  );
  assert.equal(emRow.rows[0].status, "cancelled_ride");
  assert.equal(Number(emRow.rows[0].resolved_by_user_id), adminId);

  // admins are discoverable as emergency recipients
  const recipients = await taxiRepo.listTaxiEmergencyRecipients();
  assert.ok(recipients.includes(adminId));
});
