import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => resolve(server));
  });
}

test("ready and version endpoints respond", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const readyRes = await fetch(`${base}/ready`);
    assert.ok([200, 500, 503].includes(readyRes.status));
    const ready = await readyRes.json();
    if (readyRes.status === 200 || readyRes.status === 503) {
      assert.ok(["ready", "not_ready"].includes(ready.status));
      assert.ok(ready.db);
      assert.ok(ready.redis);
      assert.ok(ready.security?.requestSigning);
      assert.ok(ready.realtime);
      assert.ok(ready.uploads);
    } else {
      assert.ok(String(ready.message || "").length > 0);
    }

    const versionRes = await fetch(`${base}/version`);
    assert.equal(versionRes.status, 200);
    const version = await versionRes.json();
    assert.ok(version.appEnv);

    const healthRes = await fetch(`${base}/health`);
    assert.ok([200, 500].includes(healthRes.status));
    if (healthRes.status === 200) {
      const health = await healthRes.json();
      assert.equal(health.status, "ok");
      assert.equal(health.service, "maslaki-api");
      assert.ok(health.db);
      assert.ok(health.redis);
      assert.ok(health.security?.requestSigning);
      assert.ok(health.realtime);
      assert.ok(health.uploads);
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
