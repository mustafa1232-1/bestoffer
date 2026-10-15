import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import {
  assertStatus,
  createActor,
  request,
  startLocalServer,
  stopLocalServer,
} from "../scripts/e2eTestUtils.js";

function makePhone(prefix = "077") {
  return `${prefix}${String(randomInt(0, 10_000_000)).padStart(8, "0")}`;
}

function makeUsername(prefix) {
  return `${prefix}_${randomUUID().replace(/-/g, "").slice(0, 8)}`.slice(0, 24);
}

async function createStaffUser({ adminRoleKey = null } = {}) {
  const staff = await createUser({
    fullName: `Ad Board Staff ${randomUUID().slice(0, 8)}`,
    username: makeUsername("ads"),
    phone: makePhone("077"),
    pinHash: await hashPin("1234"),
    block: "HQ",
    buildingNumber: "1",
    apartment: "1",
    role: "staff",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "adboard_permissions_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });
  await q(
    `UPDATE app_user
     SET admin_role_key = $2,
         is_internal_staff = TRUE,
         permission_version = permission_version + 1
     WHERE id = $1`,
    [Number(staff.id), adminRoleKey]
  );
  return staff;
}

async function cleanupUsers(userIds) {
  const ids = userIds.map(Number).filter((id) => id > 0);
  if (!ids.length) return;
  await q(`DELETE FROM admin_user_permission WHERE user_id = ANY($1::bigint[])`, [
    ids,
  ]).catch(() => {});
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [ids]).catch(
    () => {}
  );
}

test("ads_manager staff can manage ad-board endpoints only", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `adboard-rbac-${Date.now().toString(36)}`;
  const actor = createActor("ads-manager", runTag);
  actor.appFlavor = "company";
  const staff = await createStaffUser({ adminRoleKey: "ads_manager" });

  try {
    const login = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: staff.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "ads manager login");
    actor.token = String(login.data?.token || "");

    const list = await request(baseUrl, actor, "GET", "/api/admin/ad-board/items");
    assertStatus(list, 200, "ads manager ad-board list");
    assert.ok(Array.isArray(list.data), "ad-board list payload is an array");

    const createValidation = await request(
      baseUrl,
      actor,
      "POST",
      "/api/admin/ad-board/items",
      {}
    );
    assertStatus(createValidation, 400, "ads manager reaches ad-board create");

    const deniedAdminOnly = await request(
      baseUrl,
      actor,
      "GET",
      "/api/admin/store-activities"
    );
    assertStatus(deniedAdminOnly, 403, "ads manager denied admin-only route");
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([Number(staff.id)]);
  }
});

test("staff without ads permission is denied ad-board endpoints", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `adboard-deny-${Date.now().toString(36)}`;
  const actor = createActor("plain-staff", runTag);
  actor.appFlavor = "company";
  const staff = await createStaffUser();

  try {
    const login = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: staff.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "plain staff login");
    actor.token = String(login.data?.token || "");

    const denied = await request(baseUrl, actor, "GET", "/api/admin/ad-board/items");
    assertStatus(denied, 403, "plain staff denied ad-board list");
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([Number(staff.id)]);
  }
});
