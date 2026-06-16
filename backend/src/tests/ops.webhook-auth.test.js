import assert from "node:assert/strict";
import test from "node:test";

import { requireOpsWebhookApiKey } from "../ops/opsAuth.js";

function createRes() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.payload = body;
      return this;
    },
  };
}

test("webhook auth accepts matching x-ops-api-key", () => {
  const middleware = requireOpsWebhookApiKey({ opsApiKey: "secret-key" });
  const req = { headers: { "x-ops-api-key": "secret-key" } };
  const res = createRes();
  let called = false;
  middleware(req, res, () => {
    called = true;
  });
  assert.equal(called, true);
});

test("webhook auth rejects invalid key", () => {
  const middleware = requireOpsWebhookApiKey({ opsApiKey: "secret-key" });
  const req = { headers: { "x-ops-api-key": "wrong" } };
  const res = createRes();
  middleware(req, res, () => {});
  assert.equal(res.statusCode, 401);
  assert.equal(res.payload.message, "OPS_WEBHOOK_UNAUTHORIZED");
});
