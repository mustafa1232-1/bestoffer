import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

// Regression guard: GET /orders/:orderId must carry a numeric constraint so it
// does not shadow the literal /orders/current and /orders/history routes. Before
// this, GET /api/delivery/orders/current matched :orderId="current" ->
// Number("current")=NaN -> 500 (invalid input syntax for type bigint: "NaN"),
// breaking the delivery app's current-orders and history screens.
test("delivery GET /orders/:orderId is numeric-constrained and precedes current/history", () => {
  const routesPath = fileURLToPath(
    new URL("../modules/delivery/delivery.routes.js", import.meta.url)
  );
  const src = readFileSync(routesPath, "utf8").replace(/\r\n/g, "\n");

  // The parameterized detail route must be numeric-only.
  assert.ok(
    src.includes('deliveryRouter.get("/orders/:orderId(\\\\d+)", c.orderDetail)'),
    "GET /orders/:orderId must use a numeric (\\\\d+) constraint"
  );
  // The unconstrained variant must NOT exist (it would shadow the literals).
  assert.ok(
    !src.includes('deliveryRouter.get("/orders/:orderId", c.orderDetail)'),
    "unconstrained GET /orders/:orderId must not exist"
  );

  // Literal routes still present.
  assert.ok(src.includes('deliveryRouter.get("/orders/current", c.currentOrders)'));
  assert.ok(src.includes('deliveryRouter.get("/orders/history", c.history)'));
});
