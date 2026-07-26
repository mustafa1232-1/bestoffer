import assert from "node:assert/strict";
import test from "node:test";

import {
  canPayrollTransition,
  canRecalculate,
  computeNet,
  isPayrollTerminal,
} from "../modules/employees/payroll.policy.js";

test("payroll lifecycle transitions follow DRAFT->...->ARCHIVED", () => {
  assert.equal(canPayrollTransition("DRAFT", "CALCULATED"), true);
  assert.equal(canPayrollTransition("CALCULATED", "UNDER_REVIEW"), true);
  assert.equal(canPayrollTransition("UNDER_REVIEW", "APPROVED"), true);
  assert.equal(canPayrollTransition("APPROVED", "RELEASED"), true);
  assert.equal(canPayrollTransition("RELEASED", "PAID"), true);
  assert.equal(canPayrollTransition("PAID", "ACKNOWLEDGED"), true);
  assert.equal(canPayrollTransition("ACKNOWLEDGED", "ARCHIVED"), true);
  // skips and reversals
  assert.equal(canPayrollTransition("DRAFT", "APPROVED"), false);
  assert.equal(canPayrollTransition("APPROVED", "DRAFT"), false);
  assert.equal(canPayrollTransition("ARCHIVED", "PAID"), false);
  // allowed reversals for rework
  assert.equal(canPayrollTransition("UNDER_REVIEW", "CALCULATED"), true);
});

test("recalculation only in DRAFT/CALCULATED; ARCHIVED is terminal", () => {
  assert.equal(canRecalculate("DRAFT"), true);
  assert.equal(canRecalculate("CALCULATED"), true);
  assert.equal(canRecalculate("APPROVED"), false);
  assert.equal(isPayrollTerminal("ARCHIVED"), true);
  assert.equal(isPayrollTerminal("PAID"), false);
});

test("net = base + additions - deductions, floored at zero", () => {
  assert.equal(computeNet({ baseSalaryIqd: 500000, additionsIqd: 50000, deductionsIqd: 20000 }), 530000);
  assert.equal(computeNet({ baseSalaryIqd: 100000, additionsIqd: 0, deductionsIqd: 250000 }), 0);
});
