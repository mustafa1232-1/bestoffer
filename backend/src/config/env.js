import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

function readString(name, fallback = "") {
  const value = process.env[name];
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function readNumber(name, fallback, { min, max } = {}) {
  const raw = readString(name, "");
  if (!raw) return fallback;
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

function isRailwayInternalDatabaseUrl(value) {
  if (!value) return false;
  try {
    const parsed = new URL(value);
    return /(^|\.)railway\.internal$/i.test(parsed.hostname);
  } catch {
    return false;
  }
}

function isRailwayInternalRedisUrl(value) {
  if (!value) return false;
  try {
    const parsed = new URL(value);
    return /(^|\.)railway\.internal$/i.test(parsed.hostname);
  } catch {
    return false;
  }
}

function shouldPreferPublicDatabaseUrl() {
  const hasRailwayServiceBinding = Boolean(readString("RAILWAY_SERVICE_NAME", ""));
  if (!hasRailwayServiceBinding) return false;

  const entrypoint = readStringFromValue(process.argv?.[1]).replace(/\\/g, "/");
  if (entrypoint.includes("/src/scripts/")) return true;

  const hasRuntimePort = Boolean(readString("PORT", ""));
  return !hasRuntimePort;
}

function buildRailwayCliEnv() {
  const nextEnv = { ...process.env };
  delete nextEnv.RAILWAY_API_TOKEN;
  delete nextEnv.RAILWAY_TOKEN;
  delete nextEnv.RAILWAY_ENVIRONMENT_ID;
  delete nextEnv.RAILWAY_ENVIRONMENT_NAME;
  delete nextEnv.RAILWAY_PROJECT_ID;
  delete nextEnv.RAILWAY_PROJECT_NAME;
  delete nextEnv.RAILWAY_SERVICE_ID;
  delete nextEnv.RAILWAY_SERVICE_NAME;
  return nextEnv;
}

function tryReadRailwayServiceVar(serviceName, key) {
  const invocations =
    process.platform === "win32"
      ? [
          (() => {
            const appData = readStringFromValue(process.env.APPDATA);
            if (!appData) return null;
            const cliScript = path.join(
              appData,
              "npm",
              "node_modules",
              "@railway",
              "cli",
              "bin",
              "railway.js"
            );
            if (!existsSync(cliScript)) return null;
            return {
              command: process.execPath,
              args: [cliScript],
            };
          })(),
          { command: "railway", args: [] },
        ].filter(Boolean)
      : [{ command: "railway", args: [] }];

  for (const invocation of invocations) {
    try {
      const raw = execFileSync(
        invocation.command,
        [
          ...invocation.args,
          "variable",
          "list",
          "--service",
          serviceName,
          "--json",
        ],
        {
          encoding: "utf8",
          env: buildRailwayCliEnv(),
          stdio: ["ignore", "pipe", "ignore"],
        }
      );
      const payload = JSON.parse(raw);
      const value = readStringFromValue(payload?.[key]);
      if (value) return value;
    } catch {
      // Try the next available executable candidate.
    }
  }
  return "";
}

function readStringFromValue(value) {
  if (value === undefined || value === null) return "";
  return String(value).trim();
}

function resolveDatabaseUrl(primaryUrl, publicUrl) {
  const resolvedPublicUrl =
    publicUrl ||
    (isRailwayInternalDatabaseUrl(primaryUrl) && shouldPreferPublicDatabaseUrl()
      ? tryReadRailwayServiceVar("Postgres", "DATABASE_PUBLIC_URL")
      : "");
  if (
    resolvedPublicUrl &&
    isRailwayInternalDatabaseUrl(primaryUrl) &&
    shouldPreferPublicDatabaseUrl()
  ) {
    return resolvedPublicUrl;
  }
  return primaryUrl;
}

function resolveRedisUrl(primaryUrl, publicUrl) {
  const resolvedPublicUrl =
    publicUrl ||
    (isRailwayInternalRedisUrl(primaryUrl) && shouldPreferPublicDatabaseUrl()
      ? tryReadRailwayServiceVar("Redis", "REDIS_PUBLIC_URL")
      : "");
  if (
    resolvedPublicUrl &&
    isRailwayInternalRedisUrl(primaryUrl) &&
    shouldPreferPublicDatabaseUrl()
  ) {
    return resolvedPublicUrl;
  }
  return primaryUrl;
}

const databaseUrlRaw = readString("DATABASE_URL");
const databasePublicUrl = readString("DATABASE_PUBLIC_URL");
const redisUrlRaw = readString("REDIS_URL", "");
const redisPublicUrl = readString("REDIS_PUBLIC_URL", "");

export const env = {
  nodeEnv: readString("NODE_ENV", "development"),
  isProduction: readString("NODE_ENV", "development") === "production",
  appEnv: readString("APP_ENV", readString("NODE_ENV", "development")),
  appVersion: readString("APP_VERSION", "0.0.0-dev"),
  gitCommitSha: readString("GIT_COMMIT_SHA", ""),
  appClusterMode: readString(
    "APP_CLUSTER_MODE",
    "off"
  ),
  appWorkers: readNumber("APP_WORKERS", 0, { min: 0, max: 16 }),
  appClusterMaxWorkers: readNumber("APP_CLUSTER_MAX_WORKERS", 2, {
    min: 1,
    max: 16,
  }),
  appWorkerSlot: readNumber("APP_WORKER_SLOT", 0, { min: 0, max: 99 }),
  appWorkersTotal: readNumber("APP_WORKERS_TOTAL", 1, { min: 1, max: 32 }),
  host: readString("HOST", "0.0.0.0"),
  port: readNumber("PORT", 3000, { min: 1, max: 65535 }),
  orderStockReservationTtlMinutes: readNumber(
    "ORDER_STOCK_RESERVATION_TTL_MINUTES",
    30,
    { min: 1, max: 1440 }
  ),
  orderStockReservationCleanupIntervalMs: readNumber(
    "ORDER_STOCK_RESERVATION_CLEANUP_INTERVAL_MS",
    60000,
    { min: 5000, max: 3600000 }
  ),
  // Max age of a courier_presence heartbeat still counted as "online" for
  // delivery auto-assignment eligibility. The Delivery app publishes at a
  // clearly shorter cadence (COURIER_PRESENCE_INTERVAL_SECONDS on the client,
  // default 30s) so a live driver always stays inside this window.
  courierPresenceMaxAgeSeconds: readNumber(
    "COURIER_PRESENCE_MAX_AGE_SECONDS",
    90,
    { min: 20, max: 600 }
  ),
  // Recovery batch tuning (also honored by the assignment recovery worker).
  deliveryAssignmentRecoveryBatchSize: readNumber(
    "DELIVERY_ASSIGNMENT_RECOVERY_BATCH_SIZE",
    25,
    { min: 1, max: 100 }
  ),
  deliveryAssignmentRecoveryIntervalMs: readNumber(
    "DELIVERY_ASSIGNMENT_RECOVERY_INTERVAL_MS",
    15000,
    { min: 3000, max: 600000 }
  ),
  externalRailwayScriptRuntime: shouldPreferPublicDatabaseUrl(),
  databaseUrlRaw,
  databasePublicUrl,
  databaseUrl: resolveDatabaseUrl(databaseUrlRaw, databasePublicUrl),
  dbPoolTotalMax: readNumber("DB_POOL_TOTAL_MAX", 20, { min: 4, max: 400 }),
  dbPoolMax: readNumber("DB_POOL_MAX", 0, { min: 0, max: 200 }),
  dbPoolMin: readNumber("DB_POOL_MIN", 0, { min: 0, max: 50 }),
  dbIdleTimeoutMs: readNumber("DB_IDLE_TIMEOUT_MS", 30000, {
    min: 5000,
    max: 300000,
  }),
  dbConnectionTimeoutMs: readNumber("DB_CONNECTION_TIMEOUT_MS", 10000, {
    min: 1000,
    max: 60000,
  }),
  dbStatementTimeoutMs: readNumber("DB_STATEMENT_TIMEOUT_MS", 20000, {
    min: 1000,
    max: 120000,
  }),
  dbQueryTimeoutMs: readNumber("DB_QUERY_TIMEOUT_MS", 25000, {
    min: 1000,
    max: 120000,
  }),
  redisUrlRaw,
  redisPublicUrl,
  redisUrl: resolveRedisUrl(redisUrlRaw, redisPublicUrl),
  redisEnableAutoPipelining: readBoolean("REDIS_ENABLE_AUTO_PIPELINING", true),
  realtimeCrossProcessBus: readBoolean("REALTIME_CROSS_PROCESS_BUS", false),
  realtimeRedisChannel: readString(
    "REALTIME_REDIS_CHANNEL",
    "maslaki:live-events"
  ),
  supabaseRealtimeEnabled: readBoolean("SUPABASE_REALTIME_ENABLED", false),
  supabaseRealtimeMode: readString("SUPABASE_REALTIME_MODE", "dual"),
  supabaseUrl: readString("SUPABASE_URL", ""),
  supabaseAnonKey: readString("SUPABASE_ANON_KEY", ""),
  supabaseServiceRoleKey: readString("SUPABASE_SERVICE_ROLE_KEY", ""),
  supabaseJwtSecret: readString("SUPABASE_JWT_SECRET", ""),
  supabaseRealtimeOutboxMaxAttempts: readNumber(
    "SUPABASE_REALTIME_OUTBOX_MAX_ATTEMPTS",
    8,
    { min: 1, max: 100 }
  ),
  supabaseRealtimeOutboxBaseDelayMs: readNumber(
    "SUPABASE_REALTIME_OUTBOX_BASE_DELAY_MS",
    1000,
    { min: 100, max: 600000 }
  ),
  supabaseRealtimeMembershipTimeoutMs: readNumber(
    "SUPABASE_REALTIME_MEMBERSHIP_TIMEOUT_MS",
    6000,
    { min: 500, max: 60000 }
  ),
  supabaseRealtimeMembershipRetries: readNumber(
    "SUPABASE_REALTIME_MEMBERSHIP_RETRIES",
    2,
    { min: 0, max: 5 }
  ),
  supabaseRealtimePublishTimeoutMs: readNumber(
    "SUPABASE_REALTIME_PUBLISH_TIMEOUT_MS",
    8000,
    { min: 500, max: 60000 }
  ),
  supabaseRealtimeCircuitThreshold: readNumber(
    "SUPABASE_REALTIME_CIRCUIT_THRESHOLD",
    5,
    { min: 1, max: 100 }
  ),
  supabaseRealtimeCircuitCooldownMs: readNumber(
    "SUPABASE_REALTIME_CIRCUIT_COOLDOWN_MS",
    15000,
    { min: 1000, max: 600000 }
  ),
  jwtSecret: readString("JWT_SECRET"),
  jwtSecretPrevious: readString("JWT_SECRET_PREVIOUS"),
  jwtIssuer: readString("JWT_ISSUER", ""),
  jwtAudience: readString("JWT_AUDIENCE", ""),
  jwtAccessTtl: readString("JWT_ACCESS_TTL", "7d"),
  corsOrigins: readCsv("CORS_ORIGINS", ""),
  jsonBodyLimit: readString("JSON_BODY_LIMIT", "10mb"),
  uploadsDir: readString("UPLOADS_DIR", "uploads"),
  cfAccountId: readString("CF_ACCOUNT_ID", ""),
  cfR2Bucket: readString("CF_R2_BUCKET", ""),
  cfR2Endpoint: readString("CF_R2_ENDPOINT", ""),
  cfR2AccessKeyId: readString("CF_R2_ACCESS_KEY_ID", ""),
  cfR2SecretAccessKey: readString("CF_R2_SECRET_ACCESS_KEY", ""),
  cfR2PublicBaseUrl: readString("CF_R2_PUBLIC_BASE_URL", ""),
  cfR2UploadPrefix: readString("CF_R2_UPLOAD_PREFIX", "uploads"),
  cfR2MinFileSizeBytes: readNumber("CF_R2_MIN_FILE_SIZE_BYTES", 0, {
    min: 0,
    max: 104857600,
  }),
  cfStreamAccountId: readString("CF_STREAM_ACCOUNT_ID", ""),
  cfStreamApiToken: readString("CF_STREAM_API_TOKEN", ""),
  cfStreamCustomerCode: readString("CF_STREAM_CUSTOMER_CODE", ""),
  cfStreamPlaybackBaseUrl: readString("CF_STREAM_PLAYBACK_BASE_URL", ""),
  cfStreamThumbnailBaseUrl: readString("CF_STREAM_THUMBNAIL_BASE_URL", ""),
  cfStreamWebhookSecret: readString("CF_STREAM_WEBHOOK_SECRET", ""),
  socialStreamReconcileIntervalMs: readNumber(
    "SOCIAL_STREAM_RECONCILE_INTERVAL_MS",
    30000,
    { min: 5000, max: 600000 }
  ),
  socialStreamReconcileBatchSize: readNumber(
    "SOCIAL_STREAM_RECONCILE_BATCH_SIZE",
    20,
    { min: 1, max: 100 }
  ),
  // Social V3 §1: authoritative fail-closed gate for scoped stories. While
  // false, the story service rejects ANY non-global scope request before any
  // side-effect, regardless of what the client sends. Flip to true only after
  // the complete story-scope feature (authorization + read enforcement +
  // notifications + DB matrix) is implemented.
  storyAudienceScopeEnabled: readBoolean("STORY_AUDIENCE_SCOPE_ENABLED", false),
  nearbyStoresRadiusKmDefault: readNumber("NEARBY_STORES_RADIUS_KM_DEFAULT", 10, {
    min: 1,
    max: 50,
  }),
  nearbyStoresLimitDefault: readNumber("NEARBY_STORES_LIMIT_DEFAULT", 40, {
    min: 1,
    max: 200,
  }),
  adsExternalAllowedHosts: readCsv("ADS_EXTERNAL_ALLOWED_HOSTS", ""),
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
  globalRateLimitFloor: readNumber("GLOBAL_RATE_LIMIT_FLOOR", 20000, {
    min: 1000,
    max: 100000,
  }),
  publicCatalogRateLimitMaxRequests: readNumber(
    "PUBLIC_CATALOG_RATE_LIMIT_MAX_REQUESTS",
    5000,
    {
      min: 200,
      max: 50000,
    }
  ),
  rateLimitAuthMaxRequests: readNumber("RATE_LIMIT_AUTH_MAX_REQUESTS", 40, {
    min: 5,
    max: 300,
  }),
  firewallEnabled: readBoolean("FIREWALL_ENABLED", true),
  firewallAllowedMethods: readCsv(
    "FIREWALL_ALLOWED_METHODS",
    "GET,POST,PUT,PATCH,DELETE,OPTIONS"
  ),
  firewallTrustedIps: readCsv("FIREWALL_TRUSTED_IPS", ""),
  firewallMaxPathLength: readNumber("FIREWALL_MAX_PATH_LENGTH", 2048, {
    min: 256,
    max: 16384,
  }),
  firewallMaxQueryLength: readNumber("FIREWALL_MAX_QUERY_LENGTH", 4096, {
    min: 256,
    max: 32768,
  }),
  firewallMaxHeaderBytes: readNumber("FIREWALL_MAX_HEADER_BYTES", 32768, {
    min: 2048,
    max: 262144,
  }),
  firewallViolationWindowMs: readNumber("FIREWALL_VIOLATION_WINDOW_MS", 600000, {
    min: 10000,
    max: 86400000,
  }),
  firewallViolationMax: readNumber("FIREWALL_VIOLATION_MAX", 8, {
    min: 1,
    max: 100,
  }),
  firewallBlockDurationMs: readNumber("FIREWALL_BLOCK_DURATION_MS", 1800000, {
    min: 10000,
    max: 86400000,
  }),
  firewallBlockBadUserAgent: readBoolean("FIREWALL_BLOCK_BAD_USER_AGENT", true),
  firewallBlockSqli: readBoolean("FIREWALL_BLOCK_SQLI", true),
  firewallBlockXss: readBoolean("FIREWALL_BLOCK_XSS", true),
  firewallBlockPathTraversal: readBoolean("FIREWALL_BLOCK_PATH_TRAVERSAL", true),
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
  authMaxActiveSessionsPerUser: readNumber("AUTH_MAX_ACTIVE_SESSIONS_PER_USER", 30, {
    min: 1,
    max: 100,
  }),
  authDeviceBindingRequired: readBoolean("AUTH_DEVICE_BINDING_REQUIRED", true),
  authAllowLegacyTokens: readBoolean("AUTH_ALLOW_LEGACY_TOKENS", false),
  authSessionTouchIntervalSec: readNumber("AUTH_SESSION_TOUCH_INTERVAL_SEC", 60, {
    min: 10,
    max: 600,
  }),
  securityRequestSigningEnabled: readBoolean(
    "SECURITY_REQUEST_SIGNING_ENABLED",
    readString("NODE_ENV", "development") === "production"
  ),
  securityRequestSigningTtlSec: readNumber(
    "SECURITY_REQUEST_SIGNING_TTL_SEC",
    15 * 60,
    {
      min: 60,
      max: 24 * 60 * 60,
    }
  ),
  securityRequestSigningRefreshWindowSec: readNumber(
    "SECURITY_REQUEST_SIGNING_REFRESH_WINDOW_SEC",
    2 * 60,
    {
      min: 15,
      max: 60 * 60,
    }
  ),
  securityRequestSigningMaxClockSkewSec: readNumber(
    "SECURITY_REQUEST_SIGNING_MAX_CLOCK_SKEW_SEC",
    5 * 60,
    {
      min: 30,
      max: 30 * 60,
    }
  ),
  securityRequestSigningNonceTtlSec: readNumber(
    "SECURITY_REQUEST_SIGNING_NONCE_TTL_SEC",
    20 * 60,
    {
      min: 60,
      max: 24 * 60 * 60,
    }
  ),
  sentryDsn: readString("SENTRY_DSN", ""),
  sentryAuthToken: readString("SENTRY_AUTH_TOKEN", ""),
  sentryOrg: readString("SENTRY_ORG", ""),
  sentryProjectBackend: readString("SENTRY_PROJECT_BACKEND", ""),
  sentryProjectFlutter: readString("SENTRY_PROJECT_FLUTTER", ""),
  sentryServiceName: readString("SENTRY_SERVICE_NAME", "maslaki-backend"),
  ddApiKey: readString("DD_API_KEY", ""),
  ddAppKey: readString("DD_APP_KEY", ""),
  ddSite: readString("DD_SITE", "datadoghq.com"),
  ddService: readString("DD_SERVICE", "maslaki-backend"),
  ddEnv: readString("DD_ENV", readString("NODE_ENV", "development")),
  ddVersion: readString("DD_VERSION", ""),
  ddRequestLogSampleRate: readNumber(
    "DD_REQUEST_LOG_SAMPLE_RATE",
    readString("NODE_ENV", "development") === "production" ? 0 : 1,
    { min: 0, max: 1 }
  ),
  ddRequestLogSlowMs: readNumber("DD_REQUEST_LOG_SLOW_MS", 2500, {
    min: 100,
    max: 60000,
  }),
  openaiApiKey: readString("OPENAI_API_KEY", ""),
  openaiBaseUrl: readString("OPENAI_BASE_URL", "https://api.openai.com/v1"),
  openaiModelTriage: readString("OPENAI_MODEL_TRIAGE", "gpt-5.4-mini"),
  openaiModelDeepAnalysis: readString("OPENAI_MODEL_DEEP_ANALYSIS", "gpt-5.4"),
  openaiModelCodeTasks: readString("OPENAI_MODEL_CODE_TASKS", "gpt-5.3-codex"),
  githubToken: readString("GITHUB_TOKEN", ""),
  githubOwner: readString("GITHUB_OWNER", ""),
  githubRepo: readString("GITHUB_REPO", ""),
  railwayApiToken: readString("RAILWAY_API_TOKEN", ""),
  railwayProjectId: readString("RAILWAY_PROJECT_ID", ""),
  railwayEnvironmentId: readString("RAILWAY_ENVIRONMENT_ID", ""),
  railwayBestofferServiceId: readString("RAILWAY_SERVICE_BESTOFFER_ID", ""),
  railwayBestofferServiceName: readString("RAILWAY_SERVICE_BESTOFFER_NAME", "bestoffer"),
  opsApiKey: readString("OPS_API_KEY", ""),
  opsEnableAiAnalysis: readBoolean("OPS_ENABLE_AI_ANALYSIS", true),
  opsEnableAutoRestart: readBoolean("OPS_ENABLE_AUTO_RESTART", false),
  opsEnableAutoRollback: readBoolean("OPS_ENABLE_AUTO_ROLLBACK", false),
  opsEnableFeatureFlagDisable: readBoolean(
    "OPS_ENABLE_FEATURE_FLAG_DISABLE",
    false
  ),
  opsRequireSecondApprovalForCritical: readBoolean(
    "OPS_REQUIRE_SECOND_APPROVAL_FOR_CRITICAL",
    true
  ),
  featureFlagProvider: readString("FEATURE_FLAG_PROVIDER", ""),
  unleashUrl: readString("UNLEASH_URL", ""),
  unleashApiToken: readString("UNLEASH_API_TOKEN", ""),
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
  const normalizedSupabaseMode = String(env.supabaseRealtimeMode || "")
    .trim()
    .toLowerCase();
  const validSupabaseModes = new Set(["dual", "supabase_only", "sse_only"]);

  if (!env.databaseUrl) errors.push("DATABASE_URL is required");
  if (!env.jwtSecret) errors.push("JWT_SECRET is required");
  if (env.jwtSecret && env.jwtSecret.length < 32) {
    errors.push("JWT_SECRET must be at least 32 characters");
  }
  if (env.jwtSecretPrevious && env.jwtSecretPrevious.length < 32) {
    errors.push("JWT_SECRET_PREVIOUS must be at least 32 characters");
  }
  if (!env.jwtAccessTtl) {
    errors.push("JWT_ACCESS_TTL must not be empty");
  }
  if (
    env.securityRequestSigningRefreshWindowSec >=
    env.securityRequestSigningTtlSec
  ) {
    errors.push(
      "SECURITY_REQUEST_SIGNING_REFRESH_WINDOW_SEC must be lower than SECURITY_REQUEST_SIGNING_TTL_SEC"
    );
  }
  if (!validSupabaseModes.has(normalizedSupabaseMode)) {
    errors.push(
      "SUPABASE_REALTIME_MODE must be one of dual|supabase_only|sse_only"
    );
  }
  if (
    env.supabaseRealtimeEnabled === true &&
    normalizedSupabaseMode !== "sse_only"
  ) {
    if (!env.supabaseUrl) errors.push("SUPABASE_URL is required");
    if (!env.supabaseAnonKey) errors.push("SUPABASE_ANON_KEY is required");
    if (!env.supabaseServiceRoleKey) {
      errors.push("SUPABASE_SERVICE_ROLE_KEY is required");
    }
    if (!env.supabaseJwtSecret) errors.push("SUPABASE_JWT_SECRET is required");
    if (env.supabaseJwtSecret && env.supabaseJwtSecret.length < 32) {
      errors.push("SUPABASE_JWT_SECRET must be at least 32 characters");
    }
  }
  if (env.isProduction) {
    if (env.corsOrigins.length <= 0 || env.corsOrigins.includes("*")) {
      errors.push("CORS_ORIGINS must be explicitly configured in production");
    }
    if (env.authAllowLegacyTokens === true) {
      errors.push("AUTH_ALLOW_LEGACY_TOKENS must be false in production");
    }
  }

  if (errors.length) {
    const error = new Error(`ENV_INVALID: ${errors.join("; ")}`);
    error.status = 500;
    error.expose = false;
    throw error;
  }
}

export { readBoolean, readCsv, readNumber, readString };
