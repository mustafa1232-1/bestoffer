import assert from "node:assert/strict";
import test from "node:test";

import {
  ADMIN_ENDPOINT_PERMISSION_REGISTRY,
  ADMIN_PAGE_PERMISSION_REGISTRY,
  assertAdminPermissionRegistryValid,
} from "../modules/security/admin-permission.registry.js";
import { MAKER_APPROVAL_STATUS } from "../modules/security/maker-approval.service.js";
import {
  PERMISSION_KEYS,
  isValidPermissionKey,
} from "../modules/security/permissions.catalog.js";
import { signAccessToken, verifyAccessToken } from "../shared/utils/jwt.js";

test("admin permission registry only references catalog permissions", () => {
  assert.equal(assertAdminPermissionRegistryValid(), true);
  assert.ok(ADMIN_PAGE_PERMISSION_REGISTRY.length >= 10);
  assert.ok(ADMIN_ENDPOINT_PERMISSION_REGISTRY.length >= 10);
  for (const entry of [
    ...ADMIN_PAGE_PERMISSION_REGISTRY,
    ...ADMIN_ENDPOINT_PERMISSION_REGISTRY,
  ]) {
    assert.equal(
      isValidPermissionKey(entry.permission),
      true,
      `${entry.id || entry.path} uses unknown permission ${entry.permission}`
    );
  }
});

test("admin access tokens carry permission version without affecting users", () => {
  const adminToken = signAccessToken(
    {
      id: 17,
      role: "admin",
      isSuperAdmin: false,
      permissionVersion: 42,
      appSurface: "admin",
    },
    { sessionId: 99, tokenJti: "rbac-test" }
  );
  const adminPayload = verifyAccessToken(adminToken);
  assert.equal(adminPayload.pv, 42);
  assert.equal(adminPayload.sub, 17);

  const userToken = signAccessToken(
    { id: 18, role: "user", isSuperAdmin: false, appSurface: "user" },
    { sessionId: 100, tokenJti: "normal-user-test" }
  );
  const userPayload = verifyAccessToken(userToken);
  assert.equal(Object.prototype.hasOwnProperty.call(userPayload, "pv"), false);
});

test("maker approver foundation exposes terminal statuses and valid permission catalog", () => {
  assert.deepEqual(Object.keys(MAKER_APPROVAL_STATUS).sort(), [
    "APPROVED",
    "CANCELLED",
    "EXECUTED",
    "EXPIRED",
    "PENDING",
    "REJECTED",
  ]);
  assert.ok(PERMISSION_KEYS.includes("employees.permissions.manage"));
  assert.ok(PERMISSION_KEYS.includes("audit.read"));
});
