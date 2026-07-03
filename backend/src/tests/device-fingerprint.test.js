import assert from "node:assert/strict";
import test from "node:test";

import { buildDeviceFingerprint } from "../shared/utils/device-fingerprint.js";

test("buildDeviceFingerprint scopes the hash by app flavor", () => {
  const user = buildDeviceFingerprint({
    deviceId: "device-1",
    userAgent: "test-agent",
    platform: "flutter:user",
    appFlavor: "user",
    appVersion: "1.0.0",
    model: "pixel",
  });
  const company = buildDeviceFingerprint({
    deviceId: "device-1",
    userAgent: "test-agent",
    platform: "flutter:company",
    appFlavor: "company",
    appVersion: "1.0.0",
    model: "pixel",
  });

  assert.notEqual(user, company);
});
