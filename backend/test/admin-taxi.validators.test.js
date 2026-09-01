import assert from "node:assert/strict";
import test from "node:test";

import {
  validateTaxiAdminCancel,
  validateTaxiAdminOverview,
  validateTaxiCreditAdjustment,
} from "../src/modules/admin/admin.validators.js";

test("taxi overview accepts supported filters and pagination", () => {
  const result = validateTaxiAdminOverview({
    status: "ride_started",
    captainStatus: "near_exhaustion",
    q: "مصطفى",
    limit: "25",
    offset: "50",
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.value, {
    status: "ride_started",
    captainStatus: "near_exhaustion",
    search: "مصطفى",
    limit: 25,
    offset: 50,
  });
});

test("taxi overview rejects unknown filters", () => {
  assert.equal(validateTaxiAdminOverview({ status: "deleted" }).ok, false);
  assert.equal(validateTaxiAdminOverview({ captainStatus: "blocked" }).ok, false);
});

test("taxi overview accepts the active-credit filter used by Flutter", () => {
  const result = validateTaxiAdminOverview({ captainStatus: "active" });
  assert.equal(result.ok, true);
  assert.equal(result.value.captainStatus, "active");
});

test("admin cancellation always requires a meaningful reason", () => {
  assert.equal(validateTaxiAdminCancel({ reason: "" }).ok, false);
  assert.equal(validateTaxiAdminCancel({ reason: "حادث مروري" }).ok, true);
});

test("credit adjustment rejects zero and accepts bounded signed integers", () => {
  assert.equal(validateTaxiCreditAdjustment({ delta: 0, reason: "تصحيح" }).ok, false);
  assert.equal(validateTaxiCreditAdjustment({ delta: 15, reason: "تسديد نقدي" }).ok, true);
  assert.equal(validateTaxiCreditAdjustment({ delta: -2, reason: "تصحيح إداري" }).ok, true);
});
