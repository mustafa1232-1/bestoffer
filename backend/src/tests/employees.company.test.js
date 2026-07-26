import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as employees from "../modules/employees/employees.service.js";
import { listUsersForSearch } from "../modules/feed/feed.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
function makePhone() {
  seq += 1;
  return `07${String(Date.now() + seq + phoneSalt).slice(-9)}`;
}
function tag() {
  return `emp${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

const userIds = [];

async function makeUser(fullName) {
  const user = await createUser({
    fullName,
    username: tag().slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role: "user",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "emp_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

test.after(async () => {
  if (userIds.length) {
    await q(`DELETE FROM company_employee_profile WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_salary_contract WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("creating an employee marks them internal staff and records a salary contract", async () => {
  const uid = await makeUser("Employee One");
  const result = await employees.saveEmployee({
    actorUserId: uid,
    dto: {
      userId: uid,
      department: "customer_service",
      jobTitle: "Agent",
      employmentType: "full_time",
      startDate: "2026-01-01",
      baseSalaryIqd: 750000,
    },
  });
  assert.equal(result.created, true);

  const row = await q(`SELECT is_internal_staff FROM app_user WHERE id = $1`, [uid]);
  assert.equal(row.rows[0].is_internal_staff, true);

  const profile = await employees.getEmployeeProfile(uid);
  assert.equal(profile.employee.department, "customer_service");
  assert.equal(Number(profile.employee.base_salary_iqd), 750000);
  assert.equal(profile.salaryHistory.length >= 1, true);
});

test("salary updates append a new dated contract without replacing history", async () => {
  const uid = await makeUser("Employee Two");
  await employees.saveEmployee({
    actorUserId: uid,
    dto: { userId: uid, department: "delivery", baseSalaryIqd: 500000, startDate: "2026-01-01" },
  });
  await employees.updateSalary({
    actorUserId: uid,
    userId: uid,
    dto: { baseSalaryIqd: 600000, effectiveFrom: "2026-06-01", reason: "raise" },
  });
  const profile = await employees.getEmployeeProfile(uid);
  assert.equal(Number(profile.employee.base_salary_iqd), 600000);
  assert.ok(profile.salaryHistory.length >= 2, "history retains prior contracts");
});

test("internal staff are hidden from community user search (backend-enforced)", async () => {
  const viewer = await makeUser("Viewer Person");
  const uniqueName = `Zeta ${tag()}`;
  const staff = await makeUser(uniqueName);
  const normalUser = await makeUser(uniqueName);

  // before: both appear for the same search term
  let results = await listUsersForSearch({ viewerUserId: viewer, search: uniqueName, limit: 50 });
  let ids = results.map((r) => Number(r.id));
  assert.ok(ids.includes(staff));
  assert.ok(ids.includes(normalUser));

  // make one of them internal staff
  await employees.saveEmployee({
    actorUserId: viewer,
    dto: { userId: staff, department: "monitoring" },
  });

  // after: staff is filtered out, the normal user remains
  results = await listUsersForSearch({ viewerUserId: viewer, search: uniqueName, limit: 50 });
  ids = results.map((r) => Number(r.id));
  assert.ok(!ids.includes(staff), "internal staff must not surface in community search");
  assert.ok(ids.includes(normalUser), "normal users still surface");
});
