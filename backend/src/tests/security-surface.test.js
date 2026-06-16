import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("uploads fallback responses carry hardened headers", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const response = await fetch(`${base}/uploads/security-surface-test.jpg`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.equal(
      response.headers.get("cross-origin-resource-policy"),
      "cross-origin"
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("firewall blocks known scanner user agents", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const response = await fetch(`${base}/ready`, {
      headers: {
        "User-Agent": "sqlmap/1.8",
      },
    });
    assert.equal(response.status, 403);
    const payload = await response.json();
    assert.equal(payload.message, "FIREWALL_BLOCKED_REQUEST");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
