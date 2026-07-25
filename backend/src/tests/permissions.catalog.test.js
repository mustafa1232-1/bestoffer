import assert from "node:assert/strict";
import test from "node:test";

import {
  PERMISSION_KEYS,
  PERMISSION_SCOPES,
  ROLE_TEMPLATES,
  ROLE_TEMPLATE_KEYS,
  WILDCARD_PERMISSION,
  isValidPermissionKey,
  isValidScope,
  scopeSatisfies,
} from "../modules/security/permissions.catalog.js";

test("permission keys are unique and non-empty", () => {
  const set = new Set(PERMISSION_KEYS);
  assert.equal(set.size, PERMISSION_KEYS.length, "duplicate permission keys");
  for (const key of PERMISSION_KEYS) {
    assert.ok(key && typeof key === "string" && key.trim() === key, `bad key: ${key}`);
  }
});

test("every role template references only valid permission keys (or wildcard)", () => {
  for (const roleKey of ROLE_TEMPLATE_KEYS) {
    for (const key of ROLE_TEMPLATES[roleKey]) {
      if (key === WILDCARD_PERMISSION) continue;
      assert.ok(
        isValidPermissionKey(key),
        `role ${roleKey} references unknown permission ${key}`
      );
    }
  }
});

test("only super_admin holds the wildcard", () => {
  for (const roleKey of ROLE_TEMPLATE_KEYS) {
    const hasWildcard = ROLE_TEMPLATES[roleKey].includes(WILDCARD_PERMISSION);
    if (roleKey === "super_admin") assert.ok(hasWildcard);
    else assert.ok(!hasWildcard, `${roleKey} must not hold wildcard`);
  }
});

test("scope hierarchy: higher scope satisfies lower requirement", () => {
  assert.equal(scopeSatisfies("all", "own"), true);
  assert.equal(scopeSatisfies("all", "all"), true);
  assert.equal(scopeSatisfies("department", "assigned"), true);
  assert.equal(scopeSatisfies("assigned", "department"), false);
  assert.equal(scopeSatisfies("own", "all"), false);
  assert.equal(scopeSatisfies("own", "own"), true);
});

test("scope + key validators reject unknown values", () => {
  assert.equal(isValidScope("all"), true);
  assert.equal(isValidScope("galaxy"), false);
  assert.equal(isValidPermissionKey("taxi.rides.emergency_cancel"), true);
  assert.equal(isValidPermissionKey("taxi.rides.launch_rocket"), false);
  assert.deepEqual(PERMISSION_SCOPES, ["own", "assigned", "department", "all"]);
});

test("least-privilege sanity: monitoring roles cannot emergency-cancel or manage permissions", () => {
  for (const roleKey of ["taxi_monitoring", "order_monitoring", "call_center_agent"]) {
    assert.ok(!ROLE_TEMPLATES[roleKey].includes("taxi.rides.emergency_cancel"));
    assert.ok(!ROLE_TEMPLATES[roleKey].includes("employees.permissions.manage"));
    assert.ok(!ROLE_TEMPLATES[roleKey].includes("payroll.release"));
  }
});
