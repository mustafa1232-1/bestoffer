import assert from "node:assert/strict";
import test from "node:test";

import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

const { resolveTrackingViewerMode } = __ordersRepoTestables;

const order = {
  customer_user_id: 100,
  delivery_user_id: 200,
  owner_user_id: 300,
};

test("customer owner can track their order", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "user", viewerId: 100, order }),
    "customer"
  );
});

test("assigned courier can track the order", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "delivery", viewerId: 200, order }),
    "delivery"
  );
});

test("merchant owner can track the order", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "owner", viewerId: 300, order }),
    "merchant"
  );
});

test("admin can track any order", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "admin", viewerId: 999, order }),
    "admin"
  );
  assert.equal(
    resolveTrackingViewerMode({
      role: "user",
      isSuperAdmin: true,
      viewerId: 999,
      order,
    }),
    "admin"
  );
});

test("an unrelated courier is denied (null => 403)", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "delivery", viewerId: 201, order }),
    null
  );
});

test("an unrelated customer is denied", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "user", viewerId: 101, order }),
    null
  );
});

test("an unrelated merchant is denied", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "owner", viewerId: 301, order }),
    null
  );
});

test("ownership is honored even when the viewer carries another role", () => {
  // A user who is genuinely the order's customer (their own session user id)
  // can still track it; the role label does not strip ownership. This is safe
  // because the id comes from the authenticated session and cannot be forged.
  assert.equal(
    resolveTrackingViewerMode({ role: "delivery", viewerId: 100, order }),
    "customer"
  );
});

test("a courier matching no party on the order is denied", () => {
  assert.equal(
    resolveTrackingViewerMode({ role: "delivery", viewerId: 250, order }),
    null
  );
});
