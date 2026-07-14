import assert from "node:assert/strict";
import test from "node:test";

import {
  describeStreamConfig,
  streamConfigHealth,
  classifyStreamConfig,
  logStreamConfigStartup,
} from "../modules/feed/feed.stream-config.js";

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

test("classifyStreamConfig returns PRESENT/MISSING/INVALID_FORMAT only", () => {
  const c = classifyStreamConfig(full);
  assert.equal(c.CF_STREAM_API_TOKEN, "PRESENT");
  const missing = classifyStreamConfig({ ...full, cfStreamApiToken: "" });
  assert.equal(missing.CF_STREAM_API_TOKEN, "MISSING");
  const badUrl = classifyStreamConfig({ ...full, cfStreamPlaybackBaseUrl: "not-a-url" });
  assert.equal(badUrl.CF_STREAM_PLAYBACK_BASE_URL, "INVALID_FORMAT");
  const badInt = classifyStreamConfig({ ...full, socialStreamReconcileBatchSize: -3 });
  assert.equal(badInt.SOCIAL_STREAM_RECONCILE_BATCH_SIZE, "INVALID_FORMAT");
  // Never leaks values.
  assert.equal(JSON.stringify(c).includes("tok"), false);
});

test("logStreamConfigStartup prints READY / UNAVAILABLE without secrets", () => {
  const lines = [];
  logStreamConfigStartup(full, (m) => lines.push(m));
  assert.equal(lines[0], "Social Stream configuration: READY");
  lines.length = 0;
  logStreamConfigStartup({ ...full, cfStreamApiToken: "" }, (m) => lines.push(m));
  assert.match(lines[0], /^Social Stream configuration: UNAVAILABLE/);
  assert.match(lines[0], /CF_STREAM_API_TOKEN/);
  assert.equal(lines[0].includes("tok"), false);
});
