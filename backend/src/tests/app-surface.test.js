import assert from "node:assert/strict";
import test from "node:test";

import { env } from "../config/env.js";
import { resolveAccessAuth } from "../shared/middleware/access-auth.js";
import { normalizeAppSurface, resolveRequestAppSurface, isRoleAllowedForSurface } from "../shared/utils/app-surface.js";
import { signAccessToken } from "../shared/utils/jwt.js";

test("normalizeAppSurface maps legacy aliases to the new surfaces", () => {
  assert.equal(normalizeAppSurface("flutter:company"), "company");
  assert.equal(normalizeAppSurface("owner"), "store");
  assert.equal(normalizeAppSurface("support"), "company");
  assert.equal(normalizeAppSurface("operations"), "company");
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
  assert.equal(isRoleAllowedForSurface("user", "company"), false);
  assert.equal(isRoleAllowedForSurface("owner", "store"), true);
});

test("resolveAccessAuth rejects mismatched request surface before session lookup", async () => {
  const jwtSecretSnapshot = env.jwtSecret;
  try {
    if (!env.jwtSecret || String(env.jwtSecret).length < 32) {
      env.jwtSecret = "unit-test-jwt-secret-0000000000000000";
    }

    const token = signAccessToken(
      {
        id: 99,
        role: "admin",
        isSuperAdmin: true,
        appSurface: "company",
      },
      {
        sessionId: 123,
        tokenJti: "token-jti",
        deviceFingerprint: "device-hash",
      }
    );

    const req = {
      headers: {
        authorization: `Bearer ${token}`,
        "x-app-flavor": "user",
        "x-client-platform": "flutter:user",
        "user-agent": "unit-test",
      },
    };

    await assert.rejects(
      () => resolveAccessAuth(req, { strict: true }),
      (error) => error?.message === "INVALID_TOKEN"
    );

    const relaxed = await resolveAccessAuth(req, { strict: false });
    assert.equal(relaxed, null);
  } finally {
    env.jwtSecret = jwtSecretSnapshot;
  }
});

test("resolveAccessAuth enforces role, route, and claim surfaces instead of trusting X-App-Flavor alone", async () => {
  const jwtSecretSnapshot = env.jwtSecret;
  try {
    if (!env.jwtSecret || String(env.jwtSecret).length < 32) {
      env.jwtSecret = "unit-test-jwt-secret-0000000000000000";
    }

    const cases = [
      {
        label: "merchant token + X-App-Flavor=user does not open user shared APIs",
        role: "owner",
        appSurface: "store",
        headerSurface: "user",
        path: "/api/me",
      },
      {
        label: "customer token + X-App-Flavor=store does not open store routes",
        role: "user",
        appSurface: "user",
        headerSurface: "store",
        path: "/api/owner/dashboard",
      },
      {
        label: "delivery token + X-App-Flavor=taxi does not open taxi routes",
        role: "delivery",
        appSurface: "delivery",
        headerSurface: "taxi",
        path: "/api/taxi/trips",
      },
      {
        label: "taxi token + X-App-Flavor=delivery does not open delivery routes",
        role: "taxi_captain",
        appSurface: "taxi",
        headerSurface: "delivery",
        path: "/api/delivery/orders",
      },
      {
        label: "admin token does not work inside user app surface",
        role: "admin",
        appSurface: "company",
        headerSurface: "user",
        path: "/api/me",
      },
      {
        label: "guest requests without a token stay blocked from private APIs",
        noToken: true,
        path: "/api/orders",
      },
      {
        label: "claim surface mismatch is rejected even when header matches",
        role: "user",
        appSurface: "store",
        headerSurface: "user",
        path: "/api/me",
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
          (error) => error?.message === "NO_TOKEN"
        );
        continue;
      }

      const token = signAccessToken(
        {
          id: 99,
          role: entry.role,
          isSuperAdmin: entry.role === "admin",
          appSurface: entry.appSurface,
        },
        {
          sessionId: 123,
          tokenJti: "token-jti",
          deviceFingerprint: "device-hash",
        }
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
        (error) => error?.message === "INVALID_TOKEN"
      );
    }
  } finally {
    env.jwtSecret = jwtSecretSnapshot;
  }
});
