import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as perms from "../modules/security/permissions.service.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let phoneSeq = 0;
function makePhone() {
  phoneSeq += 1;
  return `07${String(Date.now() + phoneSeq + phoneSalt).slice(-9)}`;
}
function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

const createdUserIds = [];
let permissionManagerId = null;

async function makeUser(role, { superAdmin = false, adminRoleKey = null } = {}) {
  const user = await createUser({
    fullName: `RBAC ${role}`,
    username: `rbac_${suffix()}`.slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "rbac_matrix_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  createdUserIds.push(id);
  if (superAdmin || adminRoleKey) {
    await q(
      `UPDATE app_user SET is_super_admin = $2, admin_role_key = $3 WHERE id = $1`,
      [id, superAdmin, adminRoleKey]
    );
  }
  return id;
}

async function getPermissionManagerId() {
  if (permissionManagerId) return permissionManagerId;
  permissionManagerId = await makeUser("admin", { adminRoleKey: "super_admin" });
  return permissionManagerId;
}

test.after(async () => {
  if (createdUserIds.length) {
    await q(`DELETE FROM admin_user_permission WHERE user_id = ANY($1::bigint[])`, [
      createdUserIds,
    ]);
    // single-super-admin partial index: clear the flag before delete just in case
    await q(`UPDATE app_user SET is_super_admin = FALSE WHERE id = ANY($1::bigint[])`, [
      createdUserIds,
    ]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [createdUserIds]);
  }
});

test("deny by default: a plain user has no admin permissions", async () => {
  const id = await makeUser("user");
  const r = await perms.checkPermission(id, "taxi.rides.read");
  assert.equal(r.allowed, false);
  assert.equal(r.reason, "NO_PERMISSION");
});

test("role template grants exactly its keys (taxi_monitoring)", async () => {
  const id = await makeUser("user", { adminRoleKey: "taxi_monitoring" });
  assert.equal((await perms.checkPermission(id, "taxi.rides.read")).allowed, true);
  assert.equal((await perms.checkPermission(id, "taxi.rides.track_live")).allowed, true);
  // not in template
  assert.equal(
    (await perms.checkPermission(id, "taxi.rides.emergency_cancel")).allowed,
    false
  );
  assert.equal((await perms.checkPermission(id, "payroll.release")).allowed, false);
});

test("per-user grant adds a permission and revoke removes an inherited one", async () => {
  const id = await makeUser("user", { adminRoleKey: "taxi_monitoring" });

  // grant an extra capability not in the template
  await perms.grantUserPermission({
    actorUserId: await getPermissionManagerId(),
    targetUserId: id,
    permissionKey: "taxi.rides.emergency_cancel",
    scope: "all",
    effect: "grant",
  });
  assert.equal(
    (await perms.checkPermission(id, "taxi.rides.emergency_cancel")).allowed,
    true
  );

  // revoke an inherited template capability
  await perms.grantUserPermission({
    actorUserId: await getPermissionManagerId(),
    targetUserId: id,
    permissionKey: "taxi.rides.read",
    effect: "revoke",
    scope: "all",
  });
  assert.equal((await perms.checkPermission(id, "taxi.rides.read")).allowed, false);
});

test("scope: a department-scoped grant does not satisfy an all-scope requirement", async () => {
  const id = await makeUser("user");
  await perms.grantUserPermission({
    actorUserId: await getPermissionManagerId(),
    targetUserId: id,
    permissionKey: "support.tickets.read",
    scope: "department",
    effect: "grant",
  });
  assert.equal(
    (await perms.checkPermission(id, "support.tickets.read", "own")).allowed,
    true
  );
  assert.equal(
    (await perms.checkPermission(id, "support.tickets.read", "department")).allowed,
    true
  );
  assert.equal(
    (await perms.checkPermission(id, "support.tickets.read", "all")).allowed,
    false
  );
});

test("unauthorized user cannot grant a permission to self", async () => {
  const id = await makeUser("user");
  await assert.rejects(
    perms.grantUserPermission({
      actorUserId: id,
      targetUserId: id,
      permissionKey: "orders.read",
      scope: "all",
      effect: "grant",
    }),
    /FORBIDDEN_PERMISSION_MANAGER_REQUIRED/
  );
});

test("expired grants are ignored", async () => {
  const id = await makeUser("user");
  await perms.grantUserPermission({
    actorUserId: await getPermissionManagerId(),
    targetUserId: id,
    permissionKey: "reports.export",
    scope: "all",
    effect: "grant",
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
  assert.equal((await perms.checkPermission(id, "reports.export")).allowed, false);
});

test("granting bumps permission_version each time", async () => {
  const id = await makeUser("user");
  const before = (await perms.getEffectivePermissionsResponse(id)).permissionVersion;
  await perms.grantUserPermission({
    actorUserId: await getPermissionManagerId(),
    targetUserId: id,
    permissionKey: "orders.read",
    scope: "all",
    effect: "grant",
  });
  const after = (await perms.getEffectivePermissionsResponse(id)).permissionVersion;
  assert.ok(after > before, `expected version bump: ${before} -> ${after}`);
});

test("wildcard role (super_admin template) grants every key at all scopes", async () => {
  const id = await makeUser("user", { adminRoleKey: "super_admin" });
  for (const key of ["payroll.release", "accounts.delete_approve", "audit.read"]) {
    const r = await perms.checkPermission(id, key, "all");
    assert.equal(r.allowed, true, `wildcard denied ${key}`);
  }
});

test("invalid permission key is rejected on grant", async () => {
  const id = await makeUser("user");
  await assert.rejects(
    perms.grantUserPermission({
      actorUserId: await getPermissionManagerId(),
      targetUserId: id,
      permissionKey: "taxi.rides.launch_rocket",
      scope: "all",
      effect: "grant",
    })
  );
});
