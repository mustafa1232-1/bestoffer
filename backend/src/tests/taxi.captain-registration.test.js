import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import * as adminRepo from "../modules/admin/admin.repo.js";
import * as deliveryService from "../modules/delivery/delivery.service.js";
import * as taxiService from "../modules/taxi/taxi.service.js";
import * as taxiRepo from "../modules/taxi/taxi.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);

function makePhone(seed = 0) {
  const tail = String(Date.now() + Number(seed || 0) + phoneSalt).slice(-9);
  return `07${tail}`;
}

async function cleanupCaptainRegistration({ userId, phone }) {
  if (!Number.isFinite(Number(userId)) || Number(userId) <= 0) return;

  await q(
    `DELETE FROM app_notification
     WHERE type IN ('admin_delivery_pending_approval', 'admin_taxi_captain_pending_approval')
       AND (
         COALESCE(payload->>'captainUserId', '') = $1
         OR COALESCE(payload->>'deliveryUserId', '') = $1
       )`,
    [String(userId)]
  );
  await q(`DELETE FROM courier_profile WHERE user_id = $1`, [Number(userId)]);
  await q(`DELETE FROM taxi_captain_profile WHERE user_id = $1`, [Number(userId)]);
  await q(`DELETE FROM app_user WHERE id = $1`, [Number(userId)]);

  if (phone) {
    await q(`DELETE FROM user_session WHERE user_id = $1`, [Number(userId)]);
  }
}

test("delivery registration creates courier profile only", async () => {
  const phone = makePhone(17);
  let createdUserId = null;

  try {
    const result = await deliveryService.registerDelivery({
      fullName: `Delivery Pending ${Date.now()}`,
      phone,
      pin: "1234",
      block: "B1",
      buildingNumber: "B101",
      apartment: "201",
      vehicleType: "car",
      carMake: "Toyota",
      carModel: "Corolla",
      carYear: 2022,
      carColor: "White",
      plateNumber: `DL-${String(Date.now()).slice(-4)}`,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "delivery_registration_contract_v1",
    });

    createdUserId = Number(result?.user?.id || 0) || null;

    assert.equal(result.pendingApproval, true);
    assert.equal(result.user.role, "delivery");
    assert.equal(result.user.isTaxiCaptain, false);
    assert.equal(result.user.deliveryAccountApproved, false);
    assert.ok(createdUserId, "expected a created user id");

    const pendingDeliveries = await adminRepo.listPendingDeliveryAccounts();
    assert.ok(
      pendingDeliveries.some((row) => Number(row.id || 0) === createdUserId),
      "new delivery account should appear in delivery approval list"
    );

    const pendingCaptains = await adminRepo.listPendingTaxiCaptainAccounts();
    assert.equal(
      pendingCaptains.some((row) => Number(row.id || 0) === createdUserId),
      false,
      "delivery account must not appear in taxi captain approval list"
    );

    const captainProfile = await taxiRepo.getCaptainProfile(createdUserId);
    assert.equal(captainProfile, null, "delivery registration must not create taxi profile");

    const courierProfile = await q(
      `SELECT user_id, driver_type, is_app_courier, vehicle_type
       FROM courier_profile
       WHERE user_id = $1`,
      [createdUserId]
    );
    assert.equal(courierProfile.rowCount, 1);
    assert.equal(courierProfile.rows[0].driver_type, "app_driver");
    assert.equal(courierProfile.rows[0].is_app_courier, true);
    assert.equal(courierProfile.rows[0].vehicle_type, "car");
  } finally {
    await cleanupCaptainRegistration({ userId: createdUserId, phone }).catch(() => {});
  }
});

test("taxi captain registration creates a taxi-only pending approval profile", async () => {
  const phone = makePhone(31);
  let createdUserId = null;

  try {
    const result = await taxiService.registerCaptain({
      fullName: `Taxi Captain Pending ${Date.now()}`,
      phone,
      pin: "1234",
      block: "B1",
      buildingNumber: "B101",
      apartment: "201",
      vehicleType: "car",
      carMake: "Toyota",
      carModel: "Corolla",
      carYear: 2022,
      carColor: "White",
      plateNumber: `TC-${String(Date.now()).slice(-4)}`,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "taxi_registration_contract_v1",
    });

    createdUserId = Number(result?.user?.id || 0) || null;

    assert.equal(result.pendingApproval, true);
    assert.equal(result.user.role, "taxi_captain");
    assert.equal(result.user.isTaxiCaptain, true);
    assert.equal(result.user.taxiAccountApproved, false);
    assert.ok(createdUserId, "expected a created user id");

    const pendingCaptains = await adminRepo.listPendingTaxiCaptainAccounts();
    assert.ok(
      pendingCaptains.some((row) => Number(row.id || 0) === createdUserId),
      "new taxi captain should appear in taxi captain approval list"
    );

    const pendingDeliveries = await adminRepo.listPendingDeliveryAccounts();
    assert.equal(
      pendingDeliveries.some((row) => Number(row.id || 0) === createdUserId),
      false,
      "taxi captain account must not appear in delivery approval list"
    );

    const captainProfile = await taxiRepo.getCaptainProfile(createdUserId);
    assert.ok(captainProfile, "taxi captain profile should be created");
    assert.equal(captainProfile.taxi_account_approved, false);
    assert.equal(captainProfile.delivery_account_approved, true);
    assert.equal(captainProfile.car_make, "Toyota");
    assert.equal(captainProfile.car_model, "Corolla");
    assert.equal(captainProfile.car_year, 2022);
    assert.equal(captainProfile.plate_number.startsWith("TC-"), true);
    assert.equal(captainProfile.is_active, true);
  } finally {
    await cleanupCaptainRegistration({ userId: createdUserId, phone }).catch(() => {});
  }
});
