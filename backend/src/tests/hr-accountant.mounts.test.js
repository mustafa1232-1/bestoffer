import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("/api/hr and /api/accountant routers are mounted", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const hrRes = await fetch(`${base}/api/hr/dashboard`);
    const accountantRes = await fetch(`${base}/api/accountant/summary`);

    // Mounted + guarded endpoints should not return 404.
    assert.notEqual(hrRes.status, 404);
    assert.notEqual(accountantRes.status, 404);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
