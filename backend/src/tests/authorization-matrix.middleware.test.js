import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import { requirePermission } from "../shared/middleware/permission.middleware.js";
import * as perms from "../modules/security/permissions.service.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `az${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const userIds = [];

async function makeUser({ adminRoleKey = null } = {}) {
  const user = await createUser({
    fullName: `AZ ${tag()}`, username: tag().slice(0, 32), phone: makePhone(),
    pinHash: await hashPin("1234"), block: "A", buildingNumber: "1", apartment: "1",
    imageUrl: null, role: "user", analyticsConsentGranted: true,
    analyticsConsentVersion: "az_v1", analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  if (adminRoleKey) {
    await q(`UPDATE app_user SET admin_role_key = $2 WHERE id = $1`, [id, adminRoleKey]);
  }
  return id;
}

// يشغّل الـmiddleware ويعيد قيمة next (خطأ أو undefined).
function runGuard(guard, req) {
  return new Promise((resolve) => {
    guard(req, { status: () => ({ json: () => {} }) }, (err) => resolve(err));
  });
}

// مصفوفة تمثيلية: (مفتاح الصلاحية) لأهم endpoints الإدارية عبر المراحل.
const MATRIX = [
  "dashboard.command_center.view",
  "taxi.rides.read",
  "taxi.rides.emergency_cancel",
  "support.tickets.read",
  "support.tickets.assign",
  "support.tickets.resolve",
  "support.tickets.escalate",
  "employees.read",
  "employees.create",
  "employees.salary.read",
  "employees.salary.update",
  "employees.permissions.manage",
  "attendance.read",
  "payroll.prepare",
  "payroll.approve",
  "payroll.release",
  "settings.support_phone.update",
  "settings.guides.manage",
  "audit.read",
  "reports.export",
];

test.after(async () => {
  if (userIds.length) {
    await q(`DELETE FROM admin_user_permission WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("deny-by-default: a plain user is rejected on every guarded permission", async () => {
  const uid = await makeUser();
  for (const key of MATRIX) {
    const err = await runGuard(requirePermission(key), { userId: uid });
    assert.ok(err, `expected denial for ${key}`);
    assert.equal(err.status, 403);
    assert.equal(err.code, "FORBIDDEN_PERMISSION");
  }
});

test("granting a single permission opens exactly that route and no other", async () => {
  const uid = await makeUser();
  const granter = await makeUser({ adminRoleKey: "super_admin" });
  await perms.grantUserPermission({
    actorUserId: granter, targetUserId: uid,
    permissionKey: "support.tickets.read", scope: "all", effect: "grant",
  });

  const allowed = await runGuard(requirePermission("support.tickets.read"), { userId: uid });
  assert.equal(allowed, undefined, "granted route allowed");

  const denied = await runGuard(requirePermission("payroll.release"), { userId: uid });
  assert.ok(denied && denied.status === 403, "unrelated route still denied");
});

test("scope: a department grant fails an all-scope requirement but passes lower ones", async () => {
  const uid = await makeUser();
  const granter = await makeUser({ adminRoleKey: "super_admin" });
  await perms.grantUserPermission({
    actorUserId: granter, targetUserId: uid,
    permissionKey: "taxi.rides.read", scope: "department", effect: "grant",
  });
  assert.equal(
    await runGuard(requirePermission("taxi.rides.read", { scope: "own" }), { userId: uid }),
    undefined
  );
  const denied = await runGuard(
    requirePermission("taxi.rides.read", { scope: "all" }),
    { userId: uid }
  );
  assert.ok(denied && denied.status === 403, "all-scope requirement denied");
});

test("super admin bypasses every guarded permission", async () => {
  const req = { userId: await makeUser(), userIsSuperAdmin: true };
  for (const key of MATRIX) {
    const err = await runGuard(requirePermission(key, { scope: "all" }), req);
    assert.equal(err, undefined, `super admin denied ${key}`);
  }
});

test("unauthenticated request is rejected with 401 before any permission check", async () => {
  const err = await runGuard(requirePermission("audit.read"), { userId: 0 });
  assert.ok(err);
  assert.equal(err.status, 401);
});
