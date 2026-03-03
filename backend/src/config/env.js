function readString(name, fallback = "") {
  const value = process.env[name];
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function readNumber(name, fallback, { min, max } = {}) {
  const raw = readString(name, "");
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return fallback;
  if (typeof min === "number" && parsed < min) return min;
  if (typeof max === "number" && parsed > max) return max;
  return parsed;
}

function readBoolean(name, fallback = false) {
  const raw = readString(name, "");
  if (!raw) return fallback;
  const normalized = raw.toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

function readCsv(name, fallback = "") {
  const raw = readString(name, fallback);
  return raw
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

export const env = {
  nodeEnv: readString("NODE_ENV", "development"),
  isProduction: readString("NODE_ENV", "development") === "production",
  host: readString("HOST", "0.0.0.0"),
  port: readNumber("PORT", 3000, { min: 1, max: 65535 }),
  databaseUrl: readString("DATABASE_URL"),
  databasePublicUrl: readString("DATABASE_PUBLIC_URL"),
  jwtSecret: readString("JWT_SECRET"),
  jwtSecretPrevious: readString("JWT_SECRET_PREVIOUS"),
  jwtIssuer: readString("JWT_ISSUER", ""),
  jwtAudience: readString("JWT_AUDIENCE", ""),
  jwtAccessTtl: readString("JWT_ACCESS_TTL", "7d"),
  corsOrigins: readCsv("CORS_ORIGINS", "*"),
  jsonBodyLimit: readString("JSON_BODY_LIMIT", "10mb"),
  uploadsDir: readString("UPLOADS_DIR", "uploads"),
  runSqlMigrations: readBoolean("RUN_SQL_MIGRATIONS", false),
  logHttpRequests: readBoolean("LOG_HTTP_REQUESTS", true),
  requestTimeoutMs: readNumber("REQUEST_TIMEOUT_MS", 30000, {
    min: 5000,
    max: 120000,
  }),
  rateLimitWindowMs: readNumber("RATE_LIMIT_WINDOW_MS", 60000, {
    min: 1000,
    max: 3600000,
  }),
  rateLimitMaxRequests: readNumber("RATE_LIMIT_MAX_REQUESTS", 240, {
    min: 20,
    max: 10000,
  }),
  rateLimitAuthMaxRequests: readNumber("RATE_LIMIT_AUTH_MAX_REQUESTS", 40, {
    min: 5,
    max: 300,
  }),
  authMaxFailedAttempts: readNumber("AUTH_MAX_FAILED_ATTEMPTS", 8, {
    min: 3,
    max: 20,
  }),
  authLockMinutes: readNumber("AUTH_LOCK_MINUTES", 15, {
    min: 1,
    max: 240,
  }),
  authSessionTtlDays: readNumber("AUTH_SESSION_TTL_DAYS", 30, {
    min: 1,
    max: 120,
  }),
  authMaxActiveSessionsPerUser: readNumber("AUTH_MAX_ACTIVE_SESSIONS_PER_USER", 5, {
    min: 1,
    max: 30,
  }),
  authDeviceBindingRequired: readBoolean("AUTH_DEVICE_BINDING_REQUIRED", true),
  authAllowLegacyTokens: readBoolean("AUTH_ALLOW_LEGACY_TOKENS", true),
  authSessionTouchIntervalSec: readNumber("AUTH_SESSION_TOUCH_INTERVAL_SEC", 60, {
    min: 10,
    max: 600,
  }),
  superAdminPhone: readString("SUPER_ADMIN_PHONE", "07746515247"),
  superAdminPin: readString("SUPER_ADMIN_PIN", "1998"),
  superAdminName: readString("SUPER_ADMIN_NAME", "Super Admin"),
  superAdminUserId: readNumber("SUPER_ADMIN_USER_ID", 0, {
    min: 0,
    max: 9000000000,
  }),
};

export function validateRuntimeEnv() {
  const errors = [];

  if (!env.databaseUrl) errors.push("DATABASE_URL is required");
  if (!env.jwtSecret) errors.push("JWT_SECRET is required");
  if (env.jwtSecret && env.jwtSecret.length < 16) {
    errors.push("JWT_SECRET must be at least 16 characters");
  }
  if (env.jwtSecretPrevious && env.jwtSecretPrevious.length < 16) {
    errors.push("JWT_SECRET_PREVIOUS must be at least 16 characters");
  }
  if (!env.jwtAccessTtl) {
    errors.push("JWT_ACCESS_TTL must not be empty");
  }

  if (errors.length) {
    const error = new Error(`ENV_INVALID: ${errors.join("; ")}`);
    error.status = 500;
    error.expose = false;
    throw error;
  }
}

export { readBoolean, readCsv, readNumber, readString };
