import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluateTaxiCancellation,
  isTaxiCancellationLocked,
} from "../modules/taxi/taxi.cancellation.js";

test("customer may cancel while searching / negotiating / assigned", () => {
  for (const status of ["searching", "price_raise_required", "captain_assigned"]) {
    const d = evaluateTaxiCancellation({ status, actorRole: "customer" });
    assert.equal(d.outcome, "allowed", `expected allowed for ${status}`);
  }
});

test("captain may cancel only after assignment and before heading out", () => {
  assert.equal(
    evaluateTaxiCancellation({ status: "captain_assigned", actorRole: "captain" }).outcome,
    "allowed"
  );
  // captain cannot cancel a ride that is merely searching (not assigned to them)
  assert.equal(
    evaluateTaxiCancellation({ status: "searching", actorRole: "captain" }).outcome,
    "not_permitted"
  );
});

test("cancellation is LOCKED for both parties once the captain heads to the customer", () => {
  for (const status of ["captain_arriving", "ride_started"]) {
    for (const actorRole of ["customer", "captain"]) {
      const d = evaluateTaxiCancellation({ status, actorRole });
      assert.equal(d.outcome, "locked", `expected locked for ${status}/${actorRole}`);
      assert.equal(d.code, "TAXI_CANCELLATION_LOCKED");
    }
    assert.equal(isTaxiCancellationLocked(status), true);
  }
});

test("terminal rides report already_closed (idempotent no-op territory)", () => {
  for (const status of ["completed", "cancelled", "expired"]) {
    const d = evaluateTaxiCancellation({ status, actorRole: "customer" });
    assert.equal(d.outcome, "already_closed", `expected already_closed for ${status}`);
  }
});

test("active pre-lock statuses are not reported as locked", () => {
  for (const status of ["searching", "price_raise_required", "captain_assigned"]) {
    assert.equal(isTaxiCancellationLocked(status), false);
  }
});

test("status is normalized (whitespace / case tolerant)", () => {
  assert.equal(
    evaluateTaxiCancellation({ status: "  Captain_Arriving ", actorRole: "customer" }).outcome,
    "locked"
  );
});
