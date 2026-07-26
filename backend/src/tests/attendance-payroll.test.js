import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as employees from "../modules/employees/employees.service.js";
import * as attendance from "../modules/employees/attendance.repo.js";
import * as payroll from "../modules/employees/payroll.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `ap${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const userIds = [];
const runIds = [];
// شهر فريد لكل تشغيل لتفادي تعارض UNIQUE(period_month) على قاعدة QA المشتركة.
const periodMonth = `2${String(1000 + (Math.floor(Math.random() * 8999))).slice(0, 3)}-${String(1 + Math.floor(Math.random() * 12)).padStart(2, "0")}`;

async function makeEmployee(base) {
  const user = await createUser({
    fullName: `AP ${tag()}`,
    username: tag().slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A", buildingNumber: "1", apartment: "1", imageUrl: null, role: "user",
    analyticsConsentGranted: true, analyticsConsentVersion: "ap_v1",
    analyticsConsentGrantedAt: new Date().toISOString(), chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  await employees.saveEmployee({
    actorUserId: id,
    dto: { userId: id, department: "delivery", baseSalaryIqd: base, startDate: "2026-01-01" },
  });
  return id;
}

test.after(async () => {
  if (runIds.length) await q(`DELETE FROM company_payroll_run WHERE id = ANY($1::bigint[])`, [runIds]);
  if (userIds.length) {
    await q(`DELETE FROM company_attendance WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_expense_claim WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_employee_profile WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_salary_contract WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("attendance: no double open session, no checkout without checkin", async () => {
  const uid = await makeEmployee(600000);
  const first = await attendance.checkIn({ employeeUserId: uid });
  assert.equal(first.code, "OK");
  const second = await attendance.checkIn({ employeeUserId: uid });
  assert.equal(second.code, "ALREADY_CHECKED_IN");
  const out = await attendance.checkOut({ employeeUserId: uid });
  assert.equal(out.code, "OK");
  assert.ok(out.attendance.check_out_at);
  const outAgain = await attendance.checkOut({ employeeUserId: uid });
  assert.equal(outAgain.code, "NOT_CHECKED_IN");
});

test("payroll run: calculate folds approved expenses, then DRAFT->...->ARCHIVED with separation of duties", async () => {
  const preparer = await makeEmployee(0); // acts as staff actor
  const emp = await makeEmployee(500000);

  // approved expense inside the run month
  const exp = await attendance.submitExpense({
    employeeUserId: emp, category: "transport", amountIqd: 40000,
    expenseDate: `${periodMonth}-10`,
  });
  await attendance.reviewExpense({ expenseId: exp.id, status: "approved", reviewedByUserId: preparer });

  const created = await payroll.createRun({ periodMonth, createdByUserId: preparer });
  assert.equal(created.code, "OK");
  const runId = Number(created.run.id);
  runIds.push(runId);

  const calc = await payroll.calculateRun({ runId, actorUserId: preparer });
  assert.equal(calc.code, "OK");
  assert.equal(calc.run.status, "CALCULATED");

  const full = await payroll.getRun(runId);
  const item = full.items.find((i) => Number(i.employee_user_id) === emp);
  assert.ok(item, "employee item exists");
  assert.equal(Number(item.base_salary_iqd), 500000);
  assert.equal(Number(item.additions_iqd), 40000);
  assert.equal(Number(item.net_iqd), 540000);

  // CALCULATED -> UNDER_REVIEW (submitter = preparer)
  let t = await payroll.transitionRun({ runId, toStatus: "UNDER_REVIEW", actorUserId: preparer });
  assert.equal(t.code, "OK");

  // same person cannot approve (separation of duties)
  t = await payroll.transitionRun({
    runId, toStatus: "APPROVED", actorUserId: preparer, requireDistinctApprover: true,
  });
  assert.equal(t.code, "SEPARATION_OF_DUTIES");

  // a different approver can
  const approver = await makeEmployee(0);
  t = await payroll.transitionRun({
    runId, toStatus: "APPROVED", actorUserId: approver, requireDistinctApprover: true,
  });
  assert.equal(t.code, "OK");

  for (const step of ["RELEASED", "PAID", "ACKNOWLEDGED", "ARCHIVED"]) {
    t = await payroll.transitionRun({ runId, toStatus: step, actorUserId: approver });
    assert.equal(t.code, "OK", `transition to ${step}`);
  }

  // archived is terminal
  t = await payroll.transitionRun({ runId, toStatus: "PAID", actorUserId: approver });
  assert.equal(t.code, "INVALID_TRANSITION");
});
