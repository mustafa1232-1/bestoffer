import assert from "node:assert/strict";
import test from "node:test";

import { sanitizeRealtimePayload } from "../shared/realtime/realtime-sanitizer.js";

test("sanitizeRealtimePayload strips sensitive notification fields", () => {
  const out = sanitizeRealtimePayload("notification", {
    token: "secret-token",
    phone: "07700000000",
    notification: {
      id: 42,
      user_id: 5,
      type: "customer_order_status",
      title: "Order update",
      body: "ready",
      phone: "07700000000",
      payload: {
        orderId: 99,
        status: "accepted",
        accessToken: "never-ship",
        target: "order_details",
      },
    },
  });

  const serialized = JSON.stringify(out);
  assert.ok(!serialized.includes("secret-token"));
  assert.ok(!serialized.includes("never-ship"));
  assert.ok(!serialized.includes("07700000000"));
  assert.equal(out.notification.id, 42);
  assert.equal(out.notification.payload.orderId, 99);
});

test("sanitizeRealtimePayload keeps taxi location fields required by UI", () => {
  const out = sanitizeRealtimePayload("taxi_location_update", {
    rideId: 77,
    location: {
      latitude: 33.3,
      longitude: 44.4,
      headingDeg: 125,
      speedKmh: 40,
      phone: "hidden",
    },
  });

  assert.equal(out.rideId, 77);
  assert.equal(out.location.latitude, 33.3);
  assert.equal(out.location.longitude, 44.4);
  assert.equal("phone" in out.location, false);
});

test("sanitizeRealtimePayload keeps taxi offer identifiers for negotiation updates", () => {
  const out = sanitizeRealtimePayload("taxi_offer_received", {
    rideId: 77,
    offerId: 15,
    offer_id: 15,
    bidId: 15,
    bid_id: 15,
    captainId: 22,
    captain_id: 22,
    customerUserId: 7,
    customer_user_id: 7,
    secret: "do-not-ship",
    payload: {
      rideId: 77,
      offerId: 15,
      offer_id: 15,
      bidId: 15,
      bid_id: 15,
      captainId: 22,
      captain_id: 22,
      customerUserId: 7,
      customer_user_id: 7,
      phone: "07700000000",
    },
  });

  const serialized = JSON.stringify(out);
  assert.ok(!serialized.includes("do-not-ship"));
  assert.ok(!serialized.includes("07700000000"));
  assert.equal(out.rideId, 77);
  assert.equal(out.offerId, 15);
  assert.equal(out.offer_id, 15);
  assert.equal(out.bidId, 15);
  assert.equal(out.bid_id, 15);
  assert.equal(out.captainId, 22);
  assert.equal(out.captain_id, 22);
  assert.equal(out.customerUserId, 7);
  assert.equal(out.customer_user_id, 7);
});
