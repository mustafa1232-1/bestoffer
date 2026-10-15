import assert from "node:assert/strict";
import test from "node:test";

import { classifyServiceConnection } from "../shared/utils/connection-transport.js";

test("connection transport identifies Railway private networking", () => {
  assert.equal(
    classifyServiceConnection("postgresql://user:pass@postgres.railway.internal:5432/app"),
    "railway_private"
  );
  assert.equal(
    classifyServiceConnection("redis://default:pass@redis.railway.internal:6379"),
    "railway_private"
  );
});

test("connection transport identifies public proxies without exposing hosts", () => {
  assert.equal(
    classifyServiceConnection("postgresql://user:pass@centerbeam.proxy.rlwy.net:12116/app"),
    "railway_public_proxy"
  );
  assert.equal(classifyServiceConnection("postgresql://localhost:5432/app"), "local");
  assert.equal(classifyServiceConnection(""), "unconfigured");
  assert.equal(classifyServiceConnection("not-a-url"), "invalid");
});
