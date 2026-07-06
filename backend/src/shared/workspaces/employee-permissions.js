const STORE_EMPLOYEE_PERMISSION_KEYS = Object.freeze([
  "view_orders",
  "accept_orders",
  "reject_orders",
  "prepare_orders",
  "mark_order_item_unavailable",
  "assign_delivery",
  "change_order_status",
  "view_products",
  "create_products",
  "edit_products",
  "delete_products",
  "change_product_availability",
  "manage_offers",
  "post_as_store",
  "reply_messages",
  "reply_reviews",
  "view_reports",
  "view_financial_reports",
  "manage_store_profile",
  "manage_employees",
  "view_audit_log",
]);

const SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS = Object.freeze([
  "view_service_requests",
  "accept_service_requests",
  "reject_service_requests",
  "edit_services",
  "create_services",
  "delete_services",
  "manage_offers",
  "post_as_service",
  "reply_messages",
  "reply_reviews",
  "view_reports",
  "manage_service_profile",
  "manage_employees",
  "view_audit_log",
]);

function normalizeKey(value) {
  return String(value || "")
    .trim()
    .toLowerCase();
}

function toUniqueAllowedList(values, allowedSet) {
  const out = [];
  const seen = new Set();
  for (const rawValue of values) {
    const key = normalizeKey(rawValue);
    if (!key || !allowedSet.has(key) || seen.has(key)) continue;
    seen.add(key);
    out.push(key);
  }
  return out;
}

function extractPermissionCandidates(value) {
  if (Array.isArray(value)) {
    return value;
  }

  if (typeof value === "string") {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  if (value && typeof value === "object") {
    if (Array.isArray(value.permissions)) {
      return value.permissions;
    }
    if (Array.isArray(value.permissions_json)) {
      return value.permissions_json;
    }

    const out = [];
    for (const [key, enabled] of Object.entries(value)) {
      if (enabled === true) out.push(key);
    }
    return out;
  }

  return [];
}

export function normalizePermissionList(value, allowedKeys) {
  const allowedSet = new Set(
    Array.isArray(allowedKeys) ? allowedKeys.map(normalizeKey) : []
  );
  return toUniqueAllowedList(extractPermissionCandidates(value), allowedSet);
}

export function permissionMapFromList(value, allowedKeys) {
  const allowedList = Array.isArray(allowedKeys)
    ? allowedKeys.map(normalizeKey)
    : [];
  const normalized = new Set(normalizePermissionList(value, allowedList));
  return Object.fromEntries(allowedList.map((key) => [key, normalized.has(key)]));
}

export function hasPermission(value, permission) {
  const key = normalizeKey(permission);
  if (!key) return false;
  return normalizePermissionList(value, [key]).includes(key);
}

export function clampPermissionsToCatalog(value, catalog) {
  const normalizedCatalog = Array.isArray(catalog)
    ? catalog.map(normalizeKey)
    : [];
  return normalizePermissionList(value, normalizedCatalog);
}

export function getWorkspacePermissionCatalog(kind) {
  return kind === "service_provider"
    ? SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS
    : STORE_EMPLOYEE_PERMISSION_KEYS;
}

export function buildWorkspacePermissionPayload(value, kind) {
  const catalog = getWorkspacePermissionCatalog(kind);
  const permissions = normalizePermissionList(value, catalog);
  return {
    permissions,
    permissionMap: permissionMapFromList(permissions, catalog),
  };
}

export {
  SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
  STORE_EMPLOYEE_PERMISSION_KEYS,
};
