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
    assert.equal(readyRes.status, 200);
    const ready = await readyRes.json();
    assert.equal(ready.status, 'ready');

    const versionRes = await fetch(`${base}/version`);
    assert.equal(versionRes.status, 200);
    const version = await versionRes.json();
    assert.ok(version.appEnv);

    const healthRes = await fetch(`${base}/health`);
    assert.notEqual(healthRes.status, 404);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
