/* eslint-disable no-console */
import { env } from "../config/env.js";

function readString(value) {
  return String(value ?? "").trim();
}

export function parseDatabaseTarget(databaseUrl = env.databaseUrl || "") {
  const raw = readString(databaseUrl);
  if (!raw) {
    return {
      rawUrl: "",
      protocol: "",
      host: "",
      port: null,
      databaseName: "",
      username: "",
      hasPassword: false,
    };
  }

  try {
    const parsed = new URL(raw);
    return {
      rawUrl: raw,
      protocol: readString(parsed.protocol),
      host: readString(parsed.hostname),
      port: parsed.port ? Number(parsed.port) : null,
      databaseName: readString(parsed.pathname).replace(/^\/+/, ""),
      username: readString(parsed.username),
      hasPassword: readString(parsed.password).length > 0,
    };
  } catch (_) {
    return {
      rawUrl: raw,
      protocol: "",
      host: "",
      port: null,
      databaseName: "",
      username: "",
      hasPassword: false,
    };
  }
}

export function isTruthyFlag(value) {
  return ["1", "true", "yes", "on"].includes(readString(value).toLowerCase());
}

export function isProductionLikeDatabaseTarget(
  target,
  { isProduction = env.isProduction } = {}
) {
  const host = readString(target?.host).toLowerCase();
  const databaseName = readString(target?.databaseName).toLowerCase();
  if (isProduction === true) return true;
  if (!host && !databaseName) return false;

  return (
    host.includes("production") ||
    host.includes("-prod") ||
    host.startsWith("prod.") ||
    host.endsWith(".railway.app") ||
    host.endsWith(".railway.internal") ||
    databaseName.includes("production") ||
    databaseName.includes("-prod") ||
    databaseName.startsWith("prod")
  );
}

export function formatDatabaseTarget(target) {
  return {
    environment: env.appEnv || env.nodeEnv || "unknown",
    host: readString(target?.host) || "(unknown)",
    port: target?.port == null ? "(unknown)" : String(target.port),
    database: readString(target?.databaseName) || "(unknown)",
    protocol: readString(target?.protocol) || "(unknown)",
  };
}

export function assertSafeE2EDatabaseTarget({
  scriptName = "e2e",
  databaseUrl = env.databaseUrl || "",
  allowProductionOverride = process.env.ALLOW_E2E_PRODUCTION_TARGET,
  isProduction = env.isProduction,
} = {}) {
  const target = parseDatabaseTarget(databaseUrl);
  if (!target.rawUrl) {
    throw new Error("E2E_DATABASE_URL_REQUIRED");
  }

  const pretty = formatDatabaseTarget(target);
  console.log(
    `[${scriptName}] database target host=${pretty.host} port=${pretty.port} database=${pretty.database} environment=${pretty.environment}`
  );

  const productionLike = isProductionLikeDatabaseTarget(target, { isProduction });
  if (productionLike && !isTruthyFlag(allowProductionOverride)) {
    throw new Error(
      `Refusing to run ${scriptName} against a production-like database target. Set ALLOW_E2E_PRODUCTION_TARGET=true to override intentionally.`
    );
  }

  return {
    target,
    productionLike,
    allowedOverride: isTruthyFlag(allowProductionOverride),
    pretty,
  };
}
