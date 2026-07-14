import assert from "node:assert/strict";
import test from "node:test";

import { describeStreamConfig, streamConfigHealth } from "../modules/feed/feed.stream-config.js";

const full = {
  cfStreamAccountId: "acc",
  cfStreamApiToken: "tok",
  cfStreamCustomerCode: "cust",
  cfStreamPlaybackBaseUrl: "https://x",
  cfStreamThumbnailBaseUrl: "https://x",
  cfStreamWebhookSecret: "whs",
  socialStreamReconcileIntervalMs: 30000,
  socialStreamReconcileBatchSize: 20,
};

test("describeStreamConfig reports availability without leaking values", () => {
  const d = describeStreamConfig(full);
  assert.equal(d.streamAvailable, true);
  assert.equal(d.webhookConfigured, true);
  assert.equal(d.reconcileConfigured, true);
  assert.deepEqual(d.missing, []);
  // Only booleans are exposed — never the secret strings.
  for (const v of Object.values(d.checks)) assert.equal(typeof v, "boolean");
  assert.equal(JSON.stringify(d).includes("tok"), false);
  assert.equal(JSON.stringify(d).includes("whs"), false);
});

test("missing token makes stream unavailable and lists the gap", () => {
  const d = describeStreamConfig({ ...full, cfStreamApiToken: "" });
  assert.equal(d.streamAvailable, false);
  assert.ok(d.missing.includes("CF_STREAM_API_TOKEN"));
});

test("missing webhook secret flags webhook not configured", () => {
  const d = describeStreamConfig({ ...full, cfStreamWebhookSecret: "" });
  assert.equal(d.webhookConfigured, false);
});

test("streamConfigHealth is a secret-free summary", () => {
  const h = streamConfigHealth(full);
  assert.equal(h.stream, "available");
  assert.equal(h.webhook, "configured");
  assert.equal(JSON.stringify(h).includes("tok"), false);
});
