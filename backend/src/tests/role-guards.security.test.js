import assert from "node:assert/strict";
import test from "node:test";

import { requireCustomer } from "../shared/middleware/customer.middleware.js";
import { requireTaxiCaptain } from "../shared/middleware/taxi-captain.middleware.js";

function invokeMiddleware(middleware, req = {}) {
  return new Promise((resolve) => {
    middleware(req, {}, (error) => resolve(error || null));
  });
}

test("requireCustomer allows only user role", async () => {
  assert.equal(await invokeMiddleware(requireCustomer, { userRole: "user" }), null);

  const deliveryError = await invokeMiddleware(requireCustomer, {
    userRole: "delivery",
    userIsTaxiCaptain: false,
  });
  assert.equal(deliveryError?.message, "FORBIDDEN_CUSTOMER_ONLY");

  const captainError = await invokeMiddleware(requireCustomer, {
    userRole: "taxi_captain",
    userIsTaxiCaptain: true,
  });
  assert.equal(captainError?.message, "FORBIDDEN_CUSTOMER_ONLY");
});

test("requireTaxiCaptain rejects generic delivery and allows captain identities only", async () => {
  assert.equal(
    await invokeMiddleware(requireTaxiCaptain, { userRole: "taxi_captain" }),
    null
  );
  assert.equal(
    await invokeMiddleware(requireTaxiCaptain, {
      userRole: "delivery",
      userIsTaxiCaptain: true,
    }),
    null
  );

  const genericDeliveryError = await invokeMiddleware(requireTaxiCaptain, {
    userRole: "delivery",
    userIsTaxiCaptain: false,
  });
  assert.equal(genericDeliveryError?.message, "FORBIDDEN_TAXI_CAPTAIN_ONLY");
});
