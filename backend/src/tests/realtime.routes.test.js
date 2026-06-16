import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("POST /api/realtime/token requires auth", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const response = await fetch(`${base}/api/realtime/token`, {
      method: "POST",
    });
    assert.equal(response.status, 401);
    const payload = await response.json();
    assert.equal(payload.message, "NO_TOKEN");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
