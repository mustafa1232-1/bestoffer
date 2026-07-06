import assert from "node:assert/strict";
import test from "node:test";

import {
  SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
  STORE_EMPLOYEE_PERMISSION_KEYS,
  buildWorkspacePermissionPayload,
  clampPermissionsToCatalog,
  hasPermission,
  normalizePermissionList,
  permissionMapFromList,
} from "../shared/workspaces/employee-permissions.js";

test("workspace employee permission catalogs stay separated", () => {
  assert.ok(STORE_EMPLOYEE_PERMISSION_KEYS.includes("manage_employees"));
  assert.ok(STORE_EMPLOYEE_PERMISSION_KEYS.includes("view_audit_log"));
  assert.ok(!STORE_EMPLOYEE_PERMISSION_KEYS.includes("view_service_requests"));

  assert.ok(SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS.includes("view_service_requests"));
  assert.ok(SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS.includes("manage_employees"));
  assert.ok(!SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS.includes("view_orders"));
});

test("workspace permission payload filters unknown permissions and preserves catalog map", () => {
  const payload = buildWorkspacePermissionPayload(
    ["manage_employees", "view_audit_log", "view_audit_log", "nope", "  manage_employees  "],
    "merchant"
  );

  assert.deepEqual(payload.permissions, ["manage_employees", "view_audit_log"]);
  assert.equal(payload.permissionMap.manage_employees, true);
  assert.equal(payload.permissionMap.view_audit_log, true);
  assert.equal(payload.permissionMap.view_orders, false);
  assert.equal(
    Object.keys(payload.permissionMap).length,
    STORE_EMPLOYEE_PERMISSION_KEYS.length
  );
});

test("workspace permission helpers normalize legacy serialized inputs", () => {
  const normalized = normalizePermissionList(
    { permissions_json: [" view_service_requests ", "manage_employees", "bad"] },
    SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS
  );

  assert.deepEqual(normalized, ["view_service_requests", "manage_employees"]);
  assert.equal(
    hasPermission(["view_service_requests", "manage_employees"], "view_service_requests"),
    true
  );
  assert.equal(
    hasPermission(["view_service_requests"], "edit_services"),
    false
  );

  const map = permissionMapFromList(
    ["view_service_requests", "manage_employees"],
    SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS
  );
  assert.equal(map.view_service_requests, true);
  assert.equal(map.manage_employees, true);
  assert.equal(map.create_services, false);

  assert.deepEqual(
    clampPermissionsToCatalog(
      ["view_orders", "create_services", "view_service_requests"],
      SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS
    ),
    ["create_services", "view_service_requests"]
  );
});
