import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as taxiService from "../modules/taxi/taxi.service.js";
import * as monitoringRepo from "../modules/admin/monitoring.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let phoneSeq = 0;
function makePhone() {
  phoneSeq += 1;
  return `07${String(Date.now() + phoneSeq + phoneSalt).slice(-9)}`;
}
function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

const userIds = [];
const rideIds = [];

async function makeUser(role) {
  const user = await createUser({
    fullName: `MON ${role}`,
    username: `mon_${suffix()}`.slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "mon_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

async function makeRide({ customerId, captainId = null, status, cancelledNow = false, completedNow = false }) {
  const r = await q(
    `INSERT INTO taxi_ride_request
       (customer_user_id, assigned_captain_user_id, pickup_latitude, pickup_longitude,
        dropoff_latitude, dropoff_longitude, pickup_label, dropoff_label,
        proposed_fare_iqd, status,
        cancelled_at, completed_at)
     VALUES ($1,$2,33.31,44.36,33.32,44.37,'P','D',10000,$3,
        CASE WHEN $4 THEN NOW() ELSE NULL END,
        CASE WHEN $5 THEN NOW() ELSE NULL END)
     RETURNING id`,
    [customerId, captainId, status, cancelledNow, completedNow]
  );
  const id = Number(r.rows[0].id);
  rideIds.push(id);
  return id;
}

test.after(async () => {
  if (rideIds.length) {
    await q(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [rideIds]);
  }
  if (userIds.length) {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("taxi monitoring counters reflect newly created rides (delta-based)", async () => {
  const before = await taxiService.getTaxiMonitoringCounters();

  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");

  await makeRide({ customerId, captainId, status: "ride_started" }); // active
  await makeRide({ customerId, captainId, status: "captain_assigned" }); // active
  await makeRide({ customerId, status: "searching" }); // searching
  const cancelledRide = await makeRide({
    customerId,
    captainId,
    status: "cancelled",
    cancelledNow: true,
  }); // cancelled today
  await makeRide({
    customerId,
    captainId,
    status: "completed",
    completedNow: true,
  }); // completed today

  // open emergency on the active ride
  await taxiService.getTaxiMonitoringCounters(); // warm
  const emRide = await makeRide({ customerId, captainId, status: "ride_started" });
  await q(
    `INSERT INTO taxi_ride_emergency
       (ride_request_id, reported_by_user_id, reported_by_role, ride_status_at_report, category)
     VALUES ($1,$2,'customer','ride_started','safety')`,
    [emRide, customerId]
  );

  const after = await taxiService.getTaxiMonitoringCounters();

  assert.equal(after.active - before.active, 3, "active +3 (two + emergency ride)");
  assert.equal(after.searching - before.searching, 1, "searching +1");
  assert.equal(after.cancelledToday - before.cancelledToday, 1, "cancelledToday +1");
  assert.equal(after.completedToday - before.completedToday, 1, "completedToday +1");
  assert.equal(after.openEmergencies - before.openEmergencies, 1, "openEmergencies +1");
  assert.ok(cancelledRide > 0);
});

test("taxi monitoring list is server-paginated and filterable by status", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  await makeRide({ customerId, captainId, status: "captain_arriving" });

  const page = await taxiService.listRidesForMonitoring({
    status: "captain_arriving",
    limit: 5,
    offset: 0,
  });
  assert.ok(Array.isArray(page.items));
  assert.equal(page.limit, 5);
  assert.equal(page.offset, 0);
  assert.ok(typeof page.total === "number");
  for (const item of page.items) {
    assert.equal(item.status, "captain_arriving");
  }
});

test("order monitoring counters return a numeric shape", async () => {
  const counters = await monitoringRepo.getOrderMonitoringCounters();
  for (const key of ["active", "completedToday", "cancelledToday"]) {
    assert.equal(typeof counters[key], "number", `${key} should be numeric`);
    assert.ok(counters[key] >= 0);
  }
});
