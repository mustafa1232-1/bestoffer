import assert from "node:assert/strict";
import test from "node:test";

import {
  validateInviteEmployee,
  validateUpsertEmployee,
} from "../modules/hr/hr.validators.js";
import {
  validateProviderEmployeeActivityLogQuery,
  validateProviderEmployeeInviteBody,
  validateProviderEmployeeUpsertBody,
} from "../modules/services/services.validators.js";

test("hr employee validators keep permissions and active flags intact", () => {
  const invite = validateInviteEmployee({
    fullName: "Amina Saleh",
    phone: "07700000001",
    pin: "1234",
    roleTag: "supervisor",
    displayName: "Amina",
    contactEmail: "amina@example.com",
    employmentType: "part_time",
    baseSalary: 750000,
    currency: "IQD",
    workDaysPerWeek: 5,
    shiftStartTime: "09:00",
    shiftEndTime: "17:00",
    isActive: false,
    notes: "Night shift",
    permissions: ["manage_employees", "view_audit_log", "manage_employees", "bad"],
  });

  assert.equal(invite.ok, true);
  assert.deepEqual(invite.value.permissions, ["manage_employees", "view_audit_log", "manage_employees", "bad"]);
  assert.equal(invite.value.isActive, false);
  assert.equal(invite.value.roleTag, "supervisor");

  const upsert = validateUpsertEmployee({
    employeeUserId: 41,
    roleTag: "staff",
    displayName: "Amina",
    contactEmail: "amina@example.com",
    employmentType: "full_time",
    baseSalary: 800000,
    currency: "IQD",
    workDaysPerWeek: 6,
    shiftStartTime: "08:00",
    shiftEndTime: "16:00",
    isActive: true,
    notes: "Updated schedule",
    permissions: ["view_orders", "manage_employees"],
  });

  assert.equal(upsert.ok, true);
  assert.deepEqual(upsert.value.permissions, ["view_orders", "manage_employees"]);
  assert.equal(upsert.value.isActive, true);
});

test("service provider employee validators accept permission lists and reject malformed flags", () => {
  const invite = validateProviderEmployeeInviteBody({
    fullName: "Sara Ali",
    phone: "07700000002",
    pin: "1234",
    roleTag: "coordinator",
    displayName: "Sara",
    contactEmail: "sara@example.com",
    permissions: ["view_service_requests", "manage_employees"],
    isActive: true,
    notes: "Invite note",
    reason: "New branch",
  });

  assert.equal(invite.ok, true);
  assert.deepEqual(invite.value.permissions, ["view_service_requests", "manage_employees"]);
  assert.equal(invite.value.isActive, true);
  assert.equal(invite.value.reason, "New branch");

  const malformedInvite = validateProviderEmployeeInviteBody({
    fullName: "Sara Ali",
    phone: "07700000002",
    pin: "1234",
    isActive: "maybe",
  });

  assert.equal(malformedInvite.ok, false);
  assert.ok(malformedInvite.errors.includes("isActive"));

  const invalidUpsert = validateProviderEmployeeUpsertBody({
    employeeUserId: "abc",
    isActive: "maybe",
  });

  assert.equal(invalidUpsert.ok, false);
  assert.ok(invalidUpsert.errors.includes("employeeUserId"));
  assert.ok(invalidUpsert.errors.includes("isActive"));

  const logQuery = validateProviderEmployeeActivityLogQuery({
    employeeUserId: "11",
    limit: "150",
  });

  assert.equal(logQuery.ok, true);
  assert.equal(logQuery.value.employeeUserId, 11);
  assert.equal(logQuery.value.limit, 150);
});
