import assert from "node:assert/strict";
import test from "node:test";

import { validatePushTokenContext } from "../modules/notifications/notifications.service.js";
import {
  __notificationsRepoTestables,
  buildNotificationAudienceMetadata,
} from "../modules/notifications/notifications.repo.js";

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
