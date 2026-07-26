import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as guides from "../modules/guides/guides.service.js";
import * as perms from "../modules/security/permissions.service.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `gd${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const userIds = [];

async function makeUser({ adminRoleKey = null } = {}) {
  const user = await createUser({
    fullName: `GD ${tag()}`, username: tag().slice(0, 32), phone: makePhone(),
    pinHash: await hashPin("1234"), block: "A", buildingNumber: "1", apartment: "1",
    imageUrl: null, role: "user", analyticsConsentGranted: true,
    analyticsConsentVersion: "gd_v1", analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  if (adminRoleKey) {
    await q(`UPDATE app_user SET admin_role_key = $2 WHERE id = $1`, [id, adminRoleKey]);
  }
  return id;
}

test.after(async () => {
  if (userIds.length) {
    await q(`DELETE FROM admin_user_permission WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("user guide returns user sections and never permission-restricted ones", async () => {
  const guide = await guides.getGuide({ appScope: "user" });
  assert.equal(guide.appScope, "user");
  assert.ok(guide.sections.length >= 1);
  assert.ok(guide.sections.some((s) => s.key === "taxi"));
});

test("admin guide hides sections whose permission the employee lacks", async () => {
  const plain = await makeUser(); // no admin role, no perms
  const guide = await guides.getGuide({ appScope: "admin", viewerUserId: plain });
  const keys = guide.sections.map((s) => s.key);
  assert.ok(keys.includes("command_center"), "unrestricted admin section shows");
  assert.ok(!keys.includes("emergency"), "restricted emergency section hidden");
  assert.ok(!keys.includes("payroll"), "restricted payroll section hidden");
});

test("admin guide shows a restricted section once the permission is granted", async () => {
  const agent = await makeUser();
  const granter = await makeUser({ adminRoleKey: "super_admin" });
  await perms.grantUserPermission({
    actorUserId: granter, targetUserId: agent,
    permissionKey: "taxi.rides.emergency_cancel", scope: "all", effect: "grant",
  });
  const guide = await guides.getGuide({ appScope: "admin", viewerUserId: agent });
  const keys = guide.sections.map((s) => s.key);
  assert.ok(keys.includes("emergency"), "granted section now visible");
  assert.ok(!keys.includes("payroll"), "still-restricted section stays hidden");
});

test("wildcard (super_admin template) sees all admin sections", async () => {
  const sa = await makeUser({ adminRoleKey: "super_admin" });
  const guide = await guides.getGuide({ appScope: "admin", viewerUserId: sa });
  const keys = guide.sections.map((s) => s.key);
  assert.ok(keys.includes("emergency"));
  assert.ok(keys.includes("payroll"));
});
