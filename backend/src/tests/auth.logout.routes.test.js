import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function readJson(response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

test("logout routes are idempotent without auth", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    for (const path of [
      "/api/auth/logout",
      "/api/v1/auth/logout",
      "/api/auth/logout-all",
      "/api/v1/auth/logout-all",
    ]) {
      const response = await fetch(`${base}${path}`, { method: "POST" });
      assert.equal(response.status, 200, path);

      const payload = await readJson(response);
      if (path.includes("logout-all")) {
        assert.deepEqual(payload, { revokedCount: 0 }, path);
      } else {
        assert.deepEqual(payload, { revoked: false }, path);
      }
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("logout routes ignore invalid bearer tokens", async () => {
  const server = await startServer();
  const address = server.address();
  const base = `http://127.0.0.1:${address.port}`;

  try {
    for (const path of [
      "/api/auth/logout",
      "/api/v1/auth/logout",
      "/api/auth/logout-all",
      "/api/v1/auth/logout-all",
    ]) {
      const response = await fetch(`${base}${path}`, {
        method: "POST",
        headers: {
          Authorization: "Bearer definitely-not-a-real-token",
        },
      });
      assert.equal(response.status, 200, path);

      const payload = await readJson(response);
      if (path.includes("logout-all")) {
        assert.deepEqual(payload, { revokedCount: 0 }, path);
      } else {
        assert.deepEqual(payload, { revoked: false }, path);
      }
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
