import { env } from "../../config/env.js";

const DEFAULT_PRODUCTION_HOSTS = new Set([
  "bestoffer-production.up.railway.app",
]);

function trimSlashes(value = "") {
  return String(value || "").trim().replace(/^\/+|\/+$/g, "");
}

function hostFromUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return null;
  try {
    return new URL(raw).hostname.toLowerCase();
  } catch (_) {
    return null;
  }
}

function normalizeHost(value) {
  const raw = String(value || "").trim();
  if (!raw) return null;
  if (/^https?:\/\//i.test(raw)) return hostFromUrl(raw);
  return raw.replace(/:\d+$/, "").toLowerCase();
}

export function getTrustedMerchantMediaHosts() {
  const hosts = new Set();

  for (const host of DEFAULT_PRODUCTION_HOSTS) {
    hosts.add(host);
  }

  const r2Host = hostFromUrl(env.cfR2PublicBaseUrl);
  if (r2Host) hosts.add(r2Host);

  for (const configured of env.merchantMediaAllowedHosts || []) {
    const host = normalizeHost(configured);
    if (host) hosts.add(host);
  }

  if (!env.isProduction) {
    hosts.add("localhost");
    hosts.add("127.0.0.1");
    hosts.add("::1");
  }

  return hosts;
}

export function isTrustedMerchantMediaUrl(value) {
  if (value === undefined || value === null) return true;
  const raw = String(value || "").trim();
  if (!raw) return true;

  const uploadPrefix = trimSlashes(env.cfR2UploadPrefix || "uploads") || "uploads";
  if (raw.startsWith("/uploads/") || raw.startsWith(`${uploadPrefix}/`)) {
    return true;
  }

  let parsed = null;
  try {
    parsed = new URL(raw);
  } catch (_) {
    return false;
  }

  if (!["https:", "http:"].includes(parsed.protocol)) return false;
  if (env.isProduction && parsed.protocol !== "https:") return false;

  const hostname = parsed.hostname.toLowerCase();
  if (!getTrustedMerchantMediaHosts().has(hostname)) return false;

  const path = parsed.pathname || "";
  if (hostname === hostFromUrl(env.cfR2PublicBaseUrl)) return true;
  return path.startsWith("/uploads/") || path.startsWith(`/${uploadPrefix}/`);
}
