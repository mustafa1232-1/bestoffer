import assert from "node:assert/strict";
import test from "node:test";

import { requireAuth } from "../shared/middleware/auth.middleware.js";

test("requireAuth is idempotent when an earlier middleware already authenticated", async () => {
  const req = {
    userId: 42,
    userRole: "admin",
    userIsSuperAdmin: true,
    userIsTaxiCaptain: false,
    headers: {},
  };
  const res = {};

  await new Promise((resolve, reject) => {
    requireAuth(req, res, (error) => {
      if (error) reject(error);
      else resolve();
    });
  });

  assert.equal(req.userId, 42);
  assert.equal(req.userRole, "admin");
  assert.equal(req.userIsSuperAdmin, true);
});
