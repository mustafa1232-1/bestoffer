import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import * as adminRepo from "../modules/admin/admin.repo.js";
import * as deliveryService from "../modules/delivery/delivery.service.js";
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
     WHERE type = 'admin_delivery_pending_approval'
       AND COALESCE(payload->>'captainUserId', '') = $1`,
    [String(userId)]
  );
  await q(`DELETE FROM taxi_captain_profile WHERE user_id = $1`, [Number(userId)]);
  await q(`DELETE FROM app_user WHERE id = $1`, [Number(userId)]);

  if (phone) {
    await q(`DELETE FROM user_session WHERE user_id = $1`, [Number(userId)]);
  }
}

test("taxi captain registration creates a pending approval profile", async () => {
  const phone = makePhone(17);
  let createdUserId = null;

  try {
    const result = await deliveryService.registerDelivery({
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
    assert.equal(result.user.role, "delivery");
    assert.equal(result.user.isTaxiCaptain, true);
    assert.equal(result.user.deliveryAccountApproved, false);
    assert.ok(createdUserId, "expected a created user id");

    const pendingCaptains = await adminRepo.listPendingTaxiCaptainAccounts();
    assert.ok(
      pendingCaptains.some((row) => Number(row.id || 0) === createdUserId),
      "new taxi captain should appear in pending approval list"
    );

    const captainProfile = await taxiRepo.getCaptainProfile(createdUserId);
    assert.ok(captainProfile, "taxi captain profile should be created");
    assert.equal(captainProfile.car_make, "Toyota");
    assert.equal(captainProfile.car_model, "Corolla");
    assert.equal(captainProfile.car_year, 2022);
    assert.equal(captainProfile.plate_number.startsWith("TC-"), true);
    assert.equal(captainProfile.is_active, true);
  } finally {
    await cleanupCaptainRegistration({ userId: createdUserId, phone }).catch(() => {});
  }
});
