const APP_SURFACES = new Set(["user", "store", "delivery", "taxi", "company"]);

function normalizePath(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  const withoutQuery = raw.split("?")[0] || "";
  if (withoutQuery.startsWith("/api/v1/")) {
    return withoutQuery.replace(/^\/api\/v1\//, "/api/");
  }
  if (withoutQuery === "/api/v1") return "/api";
  return withoutQuery;
}

function readHeaderValue(value) {
  if (Array.isArray(value)) return String(value[0] || "").trim();
  return String(value || "").trim();
}

export function normalizeAppSurface(value) {
  const raw = readHeaderValue(value).toLowerCase();
  if (!raw) return null;

  if (APP_SURFACES.has(raw)) return raw;
  if (raw === "flutter") return null;
  if (raw === "company_portal_flutter" || raw === "company_portal") {
    return "company";
  }
  if (raw.startsWith("flutter:")) {
    const flavor = raw.slice("flutter:".length).trim();
    return APP_SURFACES.has(flavor) ? flavor : null;
  }
  if (raw.startsWith("app:")) {
    const flavor = raw.slice("app:".length).trim();
    return APP_SURFACES.has(flavor) ? flavor : null;
  }
  if (raw === "owner" || raw === "merchant" || raw === "storefront") {
    return "store";
  }
  if (raw === "courier" || raw === "delivery_worker") {
    return "delivery";
  }
  if (raw === "taxi_captain" || raw === "captain") {
    return "taxi";
  }
  if (raw === "customer" || raw === "guest" || raw === "user_app") {
    return "user";
  }
  if (
    raw === "admin" ||
    raw === "deputy_admin" ||
    raw === "super_admin" ||
    raw === "accountant" ||
    raw === "hr" ||
    raw === "support" ||
    raw === "operations" ||
    raw === "company_portal"
  ) {
    return "company";
  }
  return null;
}

export function resolveRouteAppSurface(reqOrPath) {
  const path = normalizePath(
    typeof reqOrPath === "string"
      ? reqOrPath
      : reqOrPath?.originalUrl || reqOrPath?.url || reqOrPath?.path || ""
  );
  if (!path) return null;
  if (/^\/api\/(admin|company|hr|accountant)(?:\/|$)/.test(path)) {
    return "company";
  }
  if (/^\/api\/owner(?:\/|$)/.test(path)) {
    return "store";
  }
  if (/^\/api\/delivery(?:\/|$)/.test(path)) {
    return "delivery";
  }
  if (/^\/api\/taxi(?:\/|$)/.test(path)) {
    return "taxi";
  }
  return null;
}

export function resolveRequestAppSurface(req) {
  const headerSurface = normalizeAppSurface(
    req?.headers?.["x-app-flavor"] || req?.headers?.["x-client-platform"]
  );
  if (headerSurface) return headerSurface;
  return resolveRouteAppSurface(req);
}

export function resolveRoleAppSurface(role) {
  const normalized = String(role || "").trim().toLowerCase();
  if (!normalized) return null;
  if (normalized === "user" || normalized === "customer") return "user";
  if (normalized === "owner" || normalized === "merchant") return "store";
  if (normalized === "delivery" || normalized === "courier") return "delivery";
  if (normalized === "taxi" || normalized === "taxi_captain") return "taxi";
  if (
    normalized === "company_portal" ||
    normalized === "admin" ||
    normalized === "deputy_admin" ||
    normalized === "super_admin" ||
    normalized === "accountant" ||
    normalized === "hr"
  ) {
    return "company";
  }
  return null;
}

export function isRoleAllowedForSurface(role, surface) {
  const normalizedSurface = normalizeAppSurface(surface);
  if (!normalizedSurface) return false;
  return resolveRoleAppSurface(role) === normalizedSurface;
}

