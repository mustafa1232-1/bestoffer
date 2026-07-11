import assert from "node:assert/strict";
import test from "node:test";

import { validatePushTokenContext } from "../modules/notifications/notifications.service.js";
import {
  __notificationsRepoTestables,
  buildNotificationAudienceMetadata,
} from "../modules/notifications/notifications.repo.js";
import { validateCreateThread } from "../modules/feed/feed.validators.js";

const auth = {
  userId: 42,
  sessionId: 77,
  role: "delivery",
  deviceContext: { deviceFingerprint: "device-hash" },
};

test("push registration uses authenticated session and canonical role surface", () => {
  assert.deepEqual(
    validatePushTokenContext(auth, {
      userId: 42,
      sessionId: 77,
      appFlavor: "courier",
    }),
    {
      userId: 42,
      sessionId: 77,
      appSurface: "delivery",
      deviceFingerprint: "device-hash",
    }
  );
});

test("service provider push registration resolves to the user app surface", () => {
  const ctx = validatePushTokenContext(
    {
      userId: 88,
      sessionId: 91,
      role: "service_provider",
      deviceContext: { deviceFingerprint: "provider-device" },
    },
    {
      userId: 88,
      sessionId: 91,
      appFlavor: "user",
    }
  );

  assert.deepEqual(ctx, {
    userId: 88,
    sessionId: 91,
    appSurface: "user",
    deviceFingerprint: "provider-device",
  });
});

test("push registration rejects user, session, and flavor hints that mismatch auth", () => {
  for (const body of [
    { userId: 41 },
    { sessionId: 78 },
    { appFlavor: "user" },
  ]) {
    assert.throws(
      () => validatePushTokenContext(auth, body),
      (error) =>
        error?.message === "PUSH_TOKEN_CONTEXT_MISMATCH" && error?.status === 409
    );
  }
});

test("notification audience metadata maps order and taxi roles to isolated surfaces", () => {
  assert.deepEqual(buildNotificationAudienceMetadata("user"), {
    appSurface: "user",
    roleScope: "customer",
    targetModule: "customer",
  });
  assert.equal(buildNotificationAudienceMetadata("owner").appSurface, "store");
  assert.equal(buildNotificationAudienceMetadata("delivery").appSurface, "delivery");
  assert.equal(buildNotificationAudienceMetadata("taxi_captain").appSurface, "taxi");
  assert.deepEqual(buildNotificationAudienceMetadata("service_provider"), {
    appSurface: "user",
    roleScope: "customer",
    targetModule: "customer",
  });
});

test("push message carries the canonical target app surface", () => {
  const message = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 8,
      type: "customer_order_on_the_way",
      title: "Update",
      body: "Moving",
      payload: {
        appSurface: "user",
        roleScope: "customer",
        targetModule: "customer",
      },
    },
    ["redacted-token"],
    12,
    { title: "Update", body: "Moving" },
    "user"
  );
  assert.equal(message.data.appSurface, "user");
  assert.equal(message.data.roleScope, "customer");
  assert.equal(message.data.targetModule, "customer");
});

test("listing notifications resolve to direct car and real-estate targets", () => {
  const carMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 9,
      type: "car_listing",
      title: "Car listing",
      body: "Open the listing",
      payload: {
        target: "car_listing",
        targetModule: "customer",
        entityId: 991,
      },
    },
    ["redacted-token"],
    null,
    { title: "Car listing", body: "Open the listing" },
    "user"
  );
  assert.equal(carMessage.data.target, "car_listing");
  assert.equal(carMessage.data.deepLinkTarget, "car_listing");
  assert.equal(carMessage.data.entityId, "991");

  const estateMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 10,
      type: "real_estate_listing",
      title: "Real estate listing",
      body: "Open the listing",
      payload: {
        target: "real_estate_listing",
        targetModule: "customer",
        entityId: 881,
      },
    },
    ["redacted-token"],
    null,
    { title: "Real estate listing", body: "Open the listing" },
    "user"
  );
  assert.equal(estateMessage.data.target, "real_estate_listing");
  assert.equal(estateMessage.data.deepLinkTarget, "real_estate_listing");
  assert.equal(estateMessage.data.entityId, "881");
});

test("pharmacy order notifications preserve explicit deep-link targets", () => {
  const customerMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 11,
      type: "pharmacy.order.created",
      title: "Pharmacy order created",
      body: "Open the order",
      payload: {
        target: "order_details",
        targetModule: "customer",
        orderId: 731,
        conversationId: 44,
      },
    },
    ["redacted-token"],
    731,
    { title: "Pharmacy order created", body: "Open the order" },
    "user"
  );
  assert.equal(customerMessage.data.target, "order_details");
  assert.equal(customerMessage.data.deepLinkTarget, "order_details");
  assert.equal(customerMessage.data.orderId, "731");

  const ownerMessage = __notificationsRepoTestables.buildMulticastMessage(
    {
      id: 12,
      type: "pharmacy.order.created.store",
      title: "Pharmacy order created",
      body: "Open the order",
      payload: {
        target: "owner_order_details",
        targetModule: "merchant",
        orderId: 731,
        conversationId: 44,
      },
    },
    ["redacted-token"],
    731,
    { title: "Pharmacy order created", body: "Open the order" },
    "store"
  );
  assert.equal(ownerMessage.data.target, "owner_order_details");
  assert.equal(ownerMessage.data.deepLinkTarget, "owner_order_details");
  assert.equal(ownerMessage.data.orderId, "731");
});

test("business thread validation accepts car and real-estate contexts", () => {
  assert.equal(
    validateCreateThread({
      userId: 7,
      kind: "business",
      contextType: "car_listing",
      contextId: 11,
    }).ok,
    true
  );
  assert.equal(
    validateCreateThread({
      userId: 7,
      kind: "business",
      contextType: "real_estate_listing",
      contextId: 22,
    }).ok,
    true
  );
});
