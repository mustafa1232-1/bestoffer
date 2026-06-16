import assert from "node:assert/strict";
import test from "node:test";

import { buildRequireOpsAuth } from "../ops/opsAuth.js";

test("requireOpsAuth allows super admin", async () => {
  const requireOpsAuth = buildRequireOpsAuth({
    authMiddleware: (req, res, next) => {
      req.userIsSuperAdmin = true;
      req.userRole = "admin";
      req.userId = 1;
      next();
    },
    lookupPermission: async () => false,
  });

  const middleware = requireOpsAuth("ai_dev_support_access");
  let forwardedError = null;
  await middleware({}, {}, (error) => {
    forwardedError = error || null;
  });
  assert.equal(forwardedError, null);
});

test("requireOpsAuth allows role with granted permission", async () => {
  const requireOpsAuth = buildRequireOpsAuth({
    authMiddleware: (req, res, next) => {
      req.userIsSuperAdmin = false;
      req.userRole = "admin";
      req.userId = 11;
      next();
    },
    lookupPermission: async (role, key) =>
      role === "admin" && key === "ai_dev_support_view_incidents",
  });

  const middleware = requireOpsAuth("ai_dev_support_view_incidents");
  let forwardedError = null;
  await middleware({}, {}, (error) => {
    forwardedError = error || null;
  });
  assert.equal(forwardedError, null);
});

test("requireOpsAuth blocks role without permission", async () => {
  const requireOpsAuth = buildRequireOpsAuth({
    authMiddleware: (req, res, next) => {
      req.userIsSuperAdmin = false;
      req.userRole = "admin";
      req.userId = 22;
      next();
    },
    lookupPermission: async () => false,
  });

  const middleware = requireOpsAuth("ai_dev_support_manage_settings");
  let forwardedError = null;
  await middleware({}, {}, (error) => {
    forwardedError = error || null;
  });
  assert.equal(forwardedError?.status, 403);
});
