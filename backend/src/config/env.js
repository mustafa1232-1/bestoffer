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

  if (errors.length) {
    const error = new Error(`ENV_INVALID: ${errors.join("; ")}`);
    error.status = 500;
    error.expose = false;
    throw error;
  }
}

export { readBoolean, readCsv, readNumber, readString };
