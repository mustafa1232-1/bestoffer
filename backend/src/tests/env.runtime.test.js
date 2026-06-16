import assert from "node:assert/strict";
import test from "node:test";

const ENV_KEYS = [
  "NODE_ENV",
  "DATABASE_URL",
  "DATABASE_PUBLIC_URL",
  "JWT_SECRET",
  "JWT_SECRET_PREVIOUS",
  "CORS_ORIGINS",
  "AUTH_ALLOW_LEGACY_TOKENS",
  "GLOBAL_RATE_LIMIT_FLOOR",
  "PORT",
  "RAILWAY_SERVICE_NAME",
  "SUPABASE_REALTIME_ENABLED",
  "SUPABASE_REALTIME_MODE",
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_JWT_SECRET",
];

async function withEnv(overrides, run) {
  const snapshot = {};
  for (const key of ENV_KEYS) snapshot[key] = process.env[key];
  try {
    for (const key of ENV_KEYS) delete process.env[key];
    for (const [key, value] of Object.entries(overrides || {})) {
      if (value !== undefined && value !== null) {
        process.env[key] = String(value);
      }
    }
    await run();
  } finally {
    for (const key of ENV_KEYS) {
      if (snapshot[key] === undefined) delete process.env[key];
      else process.env[key] = snapshot[key];
    }
  }
}

async function loadEnvModule() {
  const salt = `${Date.now()}-${Math.random()}`;
  return import(`../config/env.js?test=${salt}`);
}

async function withArgvEntry(entry, run) {
  const previous = process.argv[1];
  try {
    process.argv[1] = entry;
    await run();
  } finally {
    process.argv[1] = previous;
  }
}

test("validateRuntimeEnv rejects production wildcard CORS", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "*",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.throws(
        () => mod.validateRuntimeEnv(),
        /CORS_ORIGINS must be explicitly configured in production/
      );
    }
  );
});

test("validateRuntimeEnv rejects short JWT secret", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "short-secret",
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.throws(
        () => mod.validateRuntimeEnv(),
        /JWT_SECRET must be at least 32 characters/
      );
    }
  );
});

test("validateRuntimeEnv rejects legacy tokens enabled in production", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "true",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.throws(
        () => mod.validateRuntimeEnv(),
        /AUTH_ALLOW_LEGACY_TOKENS must be false in production/
      );
    }
  );
});

test("validateRuntimeEnv accepts valid production settings", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com,https://app.example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.doesNotThrow(() => mod.validateRuntimeEnv());
    }
  );
});

test("readNumber uses fallback when env var is unset or blank", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      GLOBAL_RATE_LIMIT_FLOOR: "",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.equal(mod.env.globalRateLimitFloor, 20000);
    }
  );
});

test("env prefers public database url for railway cli runs outside private network", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@postgres.railway.internal:5432/db",
      DATABASE_PUBLIC_URL: "postgres://user:pass@hopper.proxy.rlwy.net:12345/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      RAILWAY_SERVICE_NAME: "bestoffer",
      PORT: "",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.equal(
        mod.env.databaseUrl,
        "postgres://user:pass@hopper.proxy.rlwy.net:12345/db"
      );
      assert.equal(
        mod.env.databaseUrlRaw,
        "postgres://user:pass@postgres.railway.internal:5432/db"
      );
    }
  );
});

test("env keeps private railway database url inside deployed runtime", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@postgres.railway.internal:5432/db",
      DATABASE_PUBLIC_URL: "postgres://user:pass@hopper.proxy.rlwy.net:12345/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      RAILWAY_SERVICE_NAME: "bestoffer",
      PORT: "3000",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.equal(
        mod.env.databaseUrl,
        "postgres://user:pass@postgres.railway.internal:5432/db"
      );
    }
  );
});

test("env prefers public railway database url for script entrypoints even with local PORT", async () => {
  await withArgvEntry("D:/repo/backend/src/scripts/orderE2ECheck.js", async () => {
    await withEnv(
      {
        NODE_ENV: "production",
        DATABASE_URL: "postgres://user:pass@postgres.railway.internal:5432/db",
        DATABASE_PUBLIC_URL: "postgres://user:pass@hopper.proxy.rlwy.net:12345/db",
        JWT_SECRET: "x".repeat(32),
        CORS_ORIGINS: "https://example.com",
        AUTH_ALLOW_LEGACY_TOKENS: "false",
        RAILWAY_SERVICE_NAME: "bestoffer",
        PORT: "3000",
      },
      async () => {
        const mod = await loadEnvModule();
        assert.equal(
          mod.env.databaseUrl,
          "postgres://user:pass@hopper.proxy.rlwy.net:12345/db"
        );
      }
    );
  });
});

test("validateRuntimeEnv rejects invalid supabase realtime mode", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      SUPABASE_REALTIME_MODE: "broken",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.throws(
        () => mod.validateRuntimeEnv(),
        /SUPABASE_REALTIME_MODE must be one of dual\|supabase_only\|sse_only/
      );
    }
  );
});

test("validateRuntimeEnv rejects enabled supabase realtime when required keys are missing", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      SUPABASE_REALTIME_ENABLED: "true",
      SUPABASE_REALTIME_MODE: "dual",
      SUPABASE_URL: "https://demo.supabase.co",
      SUPABASE_ANON_KEY: "anon",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.throws(
        () => mod.validateRuntimeEnv(),
        /SUPABASE_SERVICE_ROLE_KEY is required/
      );
    }
  );
});

test("validateRuntimeEnv accepts sse_only mode without supabase keys", async () => {
  await withEnv(
    {
      NODE_ENV: "production",
      DATABASE_URL: "postgres://user:pass@localhost:5432/db",
      JWT_SECRET: "x".repeat(32),
      CORS_ORIGINS: "https://example.com",
      AUTH_ALLOW_LEGACY_TOKENS: "false",
      SUPABASE_REALTIME_ENABLED: "true",
      SUPABASE_REALTIME_MODE: "sse_only",
    },
    async () => {
      const mod = await loadEnvModule();
      assert.doesNotThrow(() => mod.validateRuntimeEnv());
    }
  );
});
