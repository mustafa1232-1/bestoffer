import assert from "node:assert/strict";
import test from "node:test";

import { app } from "../app.js";
import {
  assertStatus,
  buildPhone,
  createActor,
  request,
} from "../scripts/e2eTestUtils.js";

async function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("logout revokes the current session and sessions endpoint returns 401", async () => {
  const server = await startServer();
  const address = server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;
  const runTag = `logout-${Date.now().toString(36)}`;
  const actor = createActor("logout-revocation", runTag, "security-check/1");
  actor.appFlavor = "user";
  const phone = buildPhone("079", Number(String(Date.now()).slice(-8)));

  try {
    const register = await request(baseUrl, actor, "POST", "/api/auth/register", {
      fullName: `Logout Revocation ${runTag}`,
      phone,
      pin: "1234",
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "auth_session_revocation_test_v1",
    });
    assertStatus(register, 201, "register customer");
    actor.token = String(register.data?.token || "");

    const sessionsBefore = await request(baseUrl, actor, "GET", "/api/auth/sessions");
    assertStatus(sessionsBefore, 200, "sessions before logout");
    assert.equal(Array.isArray(sessionsBefore.data?.sessions), true);

    const logout = await request(baseUrl, actor, "POST", "/api/auth/logout");
    assertStatus(logout, 200, "logout");
    assert.equal(logout.data?.revoked, true);

    const sessionsAfter = await request(baseUrl, actor, "GET", "/api/auth/sessions");
    assertStatus(sessionsAfter, 401, "sessions after logout");
    assert.equal(sessionsAfter.data?.message, "INVALID_TOKEN");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
