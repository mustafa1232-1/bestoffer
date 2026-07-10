import assert from "node:assert/strict";
import test from "node:test";

import { env } from "../config/env.js";
import { resolveAccessAuth } from "../shared/middleware/access-auth.js";
import {
  isRoleAllowedForSurface,
  normalizeAppSurface,
  resolveRequestAppSurface,
  resolveRoleAppSurface,
} from "../shared/utils/app-surface.js";
import { signAccessToken } from "../shared/utils/jwt.js";

test("normalizeAppSurface maps legacy aliases to the new surfaces", () => {
  assert.equal(normalizeAppSurface("flutter:company"), "company");
  assert.equal(normalizeAppSurface("owner"), "store");
  assert.equal(normalizeAppSurface("support"), "company");
  assert.equal(normalizeAppSurface("operations"), "company");
  assert.equal(normalizeAppSurface("call_center"), "company");
  assert.equal(normalizeAppSurface("customer"), "user");
});

test("resolveRequestAppSurface prefers flavor headers and falls back to routes", () => {
  assert.equal(
    resolveRequestAppSurface({
      headers: { "x-app-flavor": "company" },
      originalUrl: "/api/me",
    }),
    "company"
  );
  assert.equal(
    resolveRequestAppSurface({
      headers: { "x-client-platform": "flutter:store" },
      originalUrl: "/api/me",
    }),
    "store"
  );
  assert.equal(
    resolveRequestAppSurface({
      headers: {},
      originalUrl: "/api/hr/dashboard",
    }),
    "company"
  );
});

test("role to surface mapping rejects cross-flavor access", () => {
  assert.equal(isRoleAllowedForSurface("admin", "company"), true);
  assert.equal(isRoleAllowedForSurface("accountant", "company"), true);
  assert.equal(isRoleAllowedForSurface("call_center", "company"), true);
  assert.equal(isRoleAllowedForSurface("user", "company"), false);
  assert.equal(isRoleAllowedForSurface("owner", "store"), true);
  assert.equal(isRoleAllowedForSurface("service_provider", "user"), true);
  assert.equal(resolveRoleAppSurface("service_provider"), "user");
  assert.equal(resolveRoleAppSurface("call_center"), "company");
});

test("resolveAccessAuth allows super_admin on the user surface but blocks other surfaces", async () => {
  const jwtSecretSnapshot = env.jwtSecret;
  const legacySnapshot = env.authAllowLegacyTokens;
  try {
    if (!env.jwtSecret || String(env.jwtSecret).length < 32) {
      env.jwtSecret = "unit-test-jwt-secret-0000000000000000";
    }
    env.authAllowLegacyTokens = true;

    const token = signAccessToken(
      {
        id: 99,
        role: "admin",
        isSuperAdmin: true,
        appSurface: "company",
      },
      {}
    );

    const userReq = {
      headers: {
        authorization: `Bearer ${token}`,
        "x-app-flavor": "user",
        "x-client-platform": "flutter:user",
        "user-agent": "unit-test",
      },
    };

    const auth = await resolveAccessAuth(userReq, { strict: true });
    assert.equal(auth.userId, 99);
    assert.equal(auth.role, "admin");
    assert.equal(auth.appSurface, "company");
    assert.equal(auth.requestSurface, "user");

    await assert.rejects(
      () =>
        resolveAccessAuth(
          {
            headers: {
              authorization: `Bearer ${token}`,
              "x-app-flavor": "store",
              "x-client-platform": "flutter:store",
              "user-agent": "unit-test",
            },
            originalUrl: "/api/owner/dashboard",
          },
          { strict: true }
        ),
          (error) =>
            error?.message === "FORBIDDEN_APP_SURFACE" && error?.status === 403
        );
  } finally {
    env.jwtSecret = jwtSecretSnapshot;
    env.authAllowLegacyTokens = legacySnapshot;
  }
});

test("resolveAccessAuth allows customer taxi polling routes on the user surface", async () => {
  const jwtSecretSnapshot = env.jwtSecret;
  const legacySnapshot = env.authAllowLegacyTokens;
  try {
    if (!env.jwtSecret || String(env.jwtSecret).length < 32) {
      env.jwtSecret = "unit-test-jwt-secret-0000000000000000";
    }
    env.authAllowLegacyTokens = true;

    const token = signAccessToken(
      {
        id: 99,
        role: "user",
        isSuperAdmin: false,
        appSurface: "user",
      },
      {}
    );

    const req = {
      headers: {
        authorization: `Bearer ${token}`,
        "x-app-flavor": "user",
        "x-client-platform": "flutter:user",
        "user-agent": "unit-test",
      },
      originalUrl: "/api/taxi/rides/current",
    };

    const auth = await resolveAccessAuth(req, { strict: true });
    assert.equal(auth.role, "user");
    assert.equal(auth.appSurface, "user");
    assert.equal(auth.requestSurface, "user");
  } finally {
    env.jwtSecret = jwtSecretSnapshot;
    env.authAllowLegacyTokens = legacySnapshot;
  }
});

test("resolveAccessAuth enforces role, route, and claim surfaces instead of trusting X-App-Flavor alone", async () => {
  const jwtSecretSnapshot = env.jwtSecret;
  const legacySnapshot = env.authAllowLegacyTokens;
  try {
    if (!env.jwtSecret || String(env.jwtSecret).length < 32) {
      env.jwtSecret = "unit-test-jwt-secret-0000000000000000";
    }
    env.authAllowLegacyTokens = true;

    const cases = [
      {
        label: "merchant token + X-App-Flavor=user does not open user shared APIs",
        role: "owner",
        appSurface: "store",
        headerSurface: "user",
        path: "/api/me",
        expectedMessage: "FORBIDDEN_APP_SURFACE",
        expectedStatus: 403,
        isSuperAdmin: false,
      },
      {
        label: "customer token + X-App-Flavor=store does not open store routes",
        role: "user",
        appSurface: "user",
        headerSurface: "store",
        path: "/api/owner/dashboard",
        expectedMessage: "FORBIDDEN_APP_SURFACE",
        expectedStatus: 403,
        isSuperAdmin: false,
      },
      {
        label: "delivery token + X-App-Flavor=taxi does not open taxi routes",
        role: "delivery",
        appSurface: "delivery",
        headerSurface: "taxi",
        path: "/api/taxi/trips",
        expectedMessage: "FORBIDDEN_APP_SURFACE",
        expectedStatus: 403,
        isSuperAdmin: false,
      },
      {
        label: "taxi token + X-App-Flavor=delivery does not open delivery routes",
        role: "taxi_captain",
        appSurface: "taxi",
        headerSurface: "delivery",
        path: "/api/delivery/orders",
        expectedMessage: "FORBIDDEN_APP_SURFACE",
        expectedStatus: 403,
        isSuperAdmin: false,
      },
      {
        label: "admin token does not work inside user app surface",
        role: "admin",
        appSurface: "company",
        headerSurface: "user",
        path: "/api/me",
        expectedMessage: "FORBIDDEN_APP_SURFACE",
        expectedStatus: 403,
        isSuperAdmin: false,
      },
      {
        label: "guest requests without a token stay blocked from private APIs",
        noToken: true,
        path: "/api/orders",
        expectedMessage: "NO_TOKEN",
        expectedStatus: 401,
      },
      {
        label: "claim surface mismatch is rejected even when header matches",
        role: "user",
        appSurface: "store",
        headerSurface: "user",
        path: "/api/me",
        expectedMessage: "INVALID_TOKEN",
        expectedStatus: 401,
        isSuperAdmin: false,
      },
    ];

    for (const entry of cases) {
      if (entry.noToken) {
        await assert.rejects(
          () =>
            resolveAccessAuth(
              {
                headers: {
                  "x-app-flavor": "user",
                  "x-client-platform": "flutter:user",
                  "user-agent": "unit-test",
                },
                originalUrl: entry.path,
              },
              { strict: true }
            ),
          (error) =>
            error?.message === entry.expectedMessage &&
            error?.status === entry.expectedStatus
        );
        continue;
      }

      const token = signAccessToken(
        {
          id: 99,
          role: entry.role,
          isSuperAdmin: entry.isSuperAdmin === true,
          appSurface: entry.appSurface,
        },
        {}
      );

      const req = {
        headers: {
          authorization: `Bearer ${token}`,
          "x-app-flavor": entry.headerSurface,
          "x-client-platform": `flutter:${entry.headerSurface}`,
          "user-agent": "unit-test",
        },
        originalUrl: entry.path,
      };

      await assert.rejects(
        () => resolveAccessAuth(req, { strict: true }),
        (error) =>
          error?.message === entry.expectedMessage &&
          error?.status === entry.expectedStatus
      );
    }
  } finally {
    env.jwtSecret = jwtSecretSnapshot;
    env.authAllowLegacyTokens = legacySnapshot;
  }
});
