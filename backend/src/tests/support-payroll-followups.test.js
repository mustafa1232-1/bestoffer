import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as employees from "../modules/employees/employees.service.js";
import * as payroll from "../modules/employees/payroll.repo.js";
import * as supportRepo from "../modules/support/support.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `fu${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
const period = () =>
  `2${String(100 + Math.floor(Math.random() * 800)).slice(0, 3)}-${String(1 + Math.floor(Math.random() * 12)).padStart(2, "0")}`;

const userIds = [];
const runIds = [];
const rideIds = [];

async function makeUser() {
  const user = await createUser({
    fullName: `FU ${tag()}`, username: tag().slice(0, 32), phone: makePhone(),
    pinHash: await hashPin("1234"), block: "A", buildingNumber: "1", apartment: "1",
    imageUrl: null, role: "user", analyticsConsentGranted: true,
    analyticsConsentVersion: "fu_v1", analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

test.after(async () => {
  if (runIds.length) await q(`DELETE FROM company_payroll_run WHERE id = ANY($1::bigint[])`, [runIds]);
  if (rideIds.length) await q(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [rideIds]);
  if (userIds.length) {
    await q(`DELETE FROM company_employee_profile WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_salary_contract WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("support link suggestions surface the reporter's recent rides", async () => {
  const customer = await makeUser();
  const r = await q(
    `INSERT INTO taxi_ride_request
       (customer_user_id, pickup_latitude, pickup_longitude, dropoff_latitude,
        dropoff_longitude, pickup_label, dropoff_label, proposed_fare_iqd, status)
     VALUES ($1,33.3,44.3,33.4,44.4,'من','إلى',10000,'completed') RETURNING id`,
    [customer]
  );
  rideIds.push(Number(r.rows[0].id));

  const out = await supportRepo.listLinkSuggestionsForUser(customer, { limit: 5 });
  assert.ok(Array.isArray(out.orders));
  assert.ok(Array.isArray(out.rides));
  assert.ok(
    out.rides.some((x) => x.entityId === Number(r.rows[0].id) && x.entityType === "ride"),
    "recent ride is suggested for linking"
  );
  assert.ok(out.rides[0].route.includes("→"), "ride suggestion shows a route");
});

test("payroll mark-paid records the payment method and it flows to the payslip", async () => {
  const preparer = await makeUser();
  const approver = await makeUser();
  const emp = await makeUser();
  await employees.saveEmployee({
    actorUserId: emp,
    dto: { userId: emp, department: "delivery", baseSalaryIqd: 500000 },
  });

  const created = await payroll.createRun({ periodMonth: period(), createdByUserId: preparer });
  const runId = Number(created.run.id);
  runIds.push(runId);
  await payroll.calculateRun({ runId, actorUserId: preparer });
  await payroll.transitionRun({ runId, toStatus: "UNDER_REVIEW", actorUserId: preparer });
  await payroll.transitionRun({ runId, toStatus: "APPROVED", actorUserId: approver, requireDistinctApprover: true });
  await payroll.transitionRun({ runId, toStatus: "RELEASED", actorUserId: approver });

  const paid = await payroll.transitionRun({
    runId, toStatus: "PAID", actorUserId: approver,
    paymentMethod: "bank_transfer", paymentReference: "TRX-99",
  });
  assert.equal(paid.code, "OK");
  assert.equal(paid.run.payment_method, "bank_transfer");
  assert.equal(paid.run.payment_reference, "TRX-99");

  const payslips = await payroll.listItemsForEmployee({ employeeUserId: emp });
  assert.ok(payslips.length >= 1);
  assert.equal(payslips[0].payment_method, "bank_transfer");
  assert.equal(Number(payslips[0].net_iqd), 500000);
});
