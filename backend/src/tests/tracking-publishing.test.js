import assert from "node:assert/strict";
import test from "node:test";

import { isCourierTrackableOrderStatus } from "../modules/orders/orders.repo.js";
import { isTaxiTrackableRideStatus } from "../modules/taxi/taxi.repo.js";

test("courier location publishing only accepts active delivery states", () => {
  assert.equal(isCourierTrackableOrderStatus("ready_for_delivery"), true);
  assert.equal(isCourierTrackableOrderStatus("on_the_way"), true);
  assert.equal(isCourierTrackableOrderStatus("arrived"), true);
  assert.equal(isCourierTrackableOrderStatus("delivered"), false);
  assert.equal(isCourierTrackableOrderStatus("cancelled"), false);
});

test("taxi location publishing only accepts active assigned ride states", () => {
  assert.equal(isTaxiTrackableRideStatus("captain_assigned"), true);
  assert.equal(isTaxiTrackableRideStatus("captain_arriving"), true);
  assert.equal(isTaxiTrackableRideStatus("ride_started"), true);
  assert.equal(isTaxiTrackableRideStatus("completed"), false);
  assert.equal(isTaxiTrackableRideStatus("expired"), false);
});
