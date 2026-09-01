import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import { evaluateCaptainRideCredits as evaluateCaptainSubscription } from "../src/modules/taxi/taxi-credit.js";

test("15-ride package exposes the agreed credit payload", () => {
  const status = evaluateCaptainSubscription({
    package_price_iqd: 10000,
    package_ride_count: 15,
    purchased_ride_credits: 15,
    consumed_ride_credits: 0,
  });
  assert.equal(status.packagePriceIqd, 10000);
  assert.equal(status.packageRideLimit, 15);
  assert.equal(status.usedRides, 0);
  assert.equal(status.remainingRides, 15);
  assert.equal(status.canAcceptRides, true);
});

test("ride fourteen triggers the final-ride warning state", () => {
  const status = evaluateCaptainSubscription({
    purchased_ride_credits: 15,
    consumed_ride_credits: 14,
  });
  assert.equal(status.completedRidesInPackage, 14);
  assert.equal(status.remainingRides, 1);
  assert.equal(status.isLastRide, true);
  assert.equal(status.canAcceptRides, true);
});

test("an exhausted package blocks accepting more rides", () => {
  const status = evaluateCaptainSubscription({
    purchased_ride_credits: 15,
    consumed_ride_credits: 15,
  });
  assert.equal(status.remainingRides, 0);
  assert.equal(status.isLastRide, false);
  assert.equal(status.canAccess, false);
  assert.equal(status.canAcceptRides, false);
  assert.equal(status.phase, "exhausted");
});

test("the 10,000 IQD package price is fixed despite legacy discounts", () => {
  const status = evaluateCaptainSubscription({
    package_price_iqd: 10000,
    package_ride_count: 15,
    purchased_ride_credits: 15,
    consumed_ride_credits: 15,
    discount_percent: 75,
  });
  assert.equal(status.discountPercent, 0);
  assert.equal(status.dueAmountIqd, 10000);
  assert.equal(status.discountedMonthlyFeeIqd, 10000);
});

test("support contacts are exposed in the Flutter API contract", () => {
  const status = evaluateCaptainSubscription(
    { purchased_ride_credits: 15, consumed_ride_credits: 14 },
    { phone: "+9647000000000", whatsapp: "9647000000000" },
  );
  assert.equal(status.supportPhone, "+9647000000000");
  assert.equal(status.supportWhatsapp, "9647000000000");
});

test("cash payment confirmation atomically claims a pending request", async () => {
  const source = await readFile(
    new URL("../src/modules/taxi/taxi.repo.js", import.meta.url),
    "utf8"
  );
  const confirmation = source.slice(
    source.indexOf("export async function confirmCaptainCashPayment"),
    source.indexOf("export async function getCaptainProfile")
  );
  assert.match(confirmation, /AND cash_payment_pending = TRUE/);
  assert.match(confirmation, /cash_payment_pending = FALSE/);
});
