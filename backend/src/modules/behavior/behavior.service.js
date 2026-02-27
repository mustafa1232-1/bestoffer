import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./behavior.repo.js";

const consentCache = new Map();
const consentCacheTtlMs = 5 * 60 * 1000;

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function trimOrNull(value) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  return out.length ? out : null;
}

function normalizeMetadata(value) {
  if (!value || typeof value !== "object") return null;
  try {
    const entries = Object.entries(value).slice(0, 32);
    const compact = {};
    for (const [key, raw] of entries) {
      const k = String(key || "").trim().slice(0, 64);
      if (!k) continue;

      if (raw === null || raw === undefined) {
        compact[k] = null;
        continue;
      }

      if (typeof raw === "string") {
        compact[k] = raw.length > 400 ? raw.slice(0, 400) : raw;
        continue;
      }

      if (typeof raw === "number" || typeof raw === "boolean") {
        compact[k] = raw;
        continue;
      }

      if (Array.isArray(raw)) {
        compact[k] = raw.slice(0, 20).map((item) =>
          typeof item === "string"
            ? item.slice(0, 120)
            : typeof item === "number" || typeof item === "boolean"
            ? item
            : String(item).slice(0, 120)
        );
        continue;
      }

      compact[k] = String(raw).slice(0, 250);
    }
    return compact;
  } catch (_) {
    return null;
  }
}

function normalizeIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwarded)
    ? forwarded[0]
    : String(forwarded || "").split(",")[0].trim();
  return firstForwarded || req.ip || req.socket?.remoteAddress || null;
}

async function hasAnalyticsConsent(userId) {
  const key = Number(userId);
  if (!Number.isInteger(key) || key <= 0) return false;

  const cached = consentCache.get(key);
  const now = Date.now();
  if (cached && cached.expiresAt > now) return cached.value === true;

  const value = await repo.hasUserAnalyticsConsent(key);
  consentCache.set(key, {
    value: value === true,
    expiresAt: now + consentCacheTtlMs,
  });
  return value === true;
}

async function canTrackUser(userId, userRole) {
  if (!userId) return false;
  if (String(userRole || "").toLowerCase() !== "user") return false;
  return hasAnalyticsConsent(userId);
}

function normalizeEventInput(body = {}) {
  const eventName = trimOrNull(body.eventName);
  if (!eventName || eventName.length > 120) {
    throw new AppError("INVALID_EVENT_NAME", { status: 400 });
  }

  const category = trimOrNull(body.category);
  const action = trimOrNull(body.action);
  const source = trimOrNull(body.source) || "app";
  const entityType = trimOrNull(body.entityType);
  const entityId =
    body.entityId === undefined || body.entityId === null
      ? null
      : Number.isInteger(Number(body.entityId)) && Number(body.entityId) > 0
      ? Number(body.entityId)
      : null;

  return {
    eventName: eventName.slice(0, 120),
    category: category ? category.slice(0, 80) : null,
    action: action ? action.slice(0, 80) : null,
    source: source.slice(0, 80),
    entityType: entityType ? entityType.slice(0, 80) : null,
    entityId,
    metadata: normalizeMetadata(body.metadata),
  };
}

export async function trackCustomEvent(userId, userRole, body, req) {
  if (!(await canTrackUser(userId, userRole))) return;

  const normalized = normalizeEventInput(body);
  await repo.insertActivityEvent({
    userId: Number(userId),
    userRole,
    ...normalized,
    path: req.originalUrl,
    method: req.method,
    statusCode: 200,
    ipAddress: normalizeIp(req),
    userAgent: req.headers["user-agent"] || null,
  });
}

export async function trackAutomaticEvent({
  userId,
  userRole,
  eventName,
  category,
  action,
  source = "api",
  path,
  method,
  entityType,
  entityId,
  statusCode,
  metadata,
  ipAddress,
  userAgent,
}) {
  if (!userId || !eventName) return;
  if (!(await canTrackUser(userId, userRole))) return;

  await repo.insertActivityEvent({
    userId: Number(userId),
    userRole,
    eventName: String(eventName).slice(0, 120),
    category: trimOrNull(category)?.slice(0, 80) || null,
    action: trimOrNull(action)?.slice(0, 80) || null,
    source: String(source || "api").slice(0, 80),
    path: trimOrNull(path),
    method: trimOrNull(method),
    entityType: trimOrNull(entityType)?.slice(0, 80) || null,
    entityId:
      Number.isInteger(Number(entityId)) && Number(entityId) > 0 ? Number(entityId) : null,
    statusCode:
      Number.isInteger(Number(statusCode)) && Number(statusCode) > 0
        ? Number(statusCode)
        : null,
    metadata: normalizeMetadata(metadata),
    ipAddress: trimOrNull(ipAddress),
    userAgent: trimOrNull(userAgent),
  });
}

export async function listMyActivityEvents(userId, query) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  return repo.listUserActivityEvents(userId, { limit });
}

function extractTopCarSignals(rows = []) {
  const brandCount = new Map();
  const modelCount = new Map();
  const usageCount = new Map();
  const budgetRanges = [];

  for (const row of rows) {
    const metadata = row.metadata && typeof row.metadata === "object" ? row.metadata : null;
    if (!metadata) continue;

    const brand = trimOrNull(metadata.brand);
    const model = trimOrNull(metadata.model);
    const usage = trimOrNull(metadata.usage);
    const budgetMin = Number(metadata.budgetMinM);
    const budgetMax = Number(metadata.budgetMaxM);

    if (brand) brandCount.set(brand, (brandCount.get(brand) || 0) + 1);
    if (model) modelCount.set(model, (modelCount.get(model) || 0) + 1);
    if (usage) usageCount.set(usage, (usageCount.get(usage) || 0) + 1);
    if (Number.isFinite(budgetMin) && Number.isFinite(budgetMax)) {
      budgetRanges.push({ min: budgetMin, max: budgetMax });
    }
  }

  const sorted = (map) =>
    [...map.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([name, count]) => ({ name, count }));

  const avgBudget =
    budgetRanges.length > 0
      ? {
          min:
            budgetRanges.reduce((acc, b) => acc + b.min, 0) / budgetRanges.length,
          max:
            budgetRanges.reduce((acc, b) => acc + b.max, 0) / budgetRanges.length,
        }
      : null;

  return {
    topBrands: sorted(brandCount),
    topModels: sorted(modelCount),
    usageModes: sorted(usageCount),
    averageBudgetM: avgBudget,
    samplesCount: budgetRanges.length,
  };
}

export async function getCustomerFullInsight(customerUserId) {
  const base = await repo.getCustomerBaseProfile(customerUserId);
  if (!base) {
    throw new AppError("CUSTOMER_NOT_FOUND", { status: 404 });
  }

  const [
    orders,
    topMerchantTypes,
    topCategories,
    topActions,
    carSignalsRows,
    lastEvents,
  ] = await Promise.all([
    repo.getCustomerOrderStats(customerUserId),
    repo.getCustomerTopMerchantTypes(customerUserId),
    repo.getCustomerTopActivityCategories(customerUserId),
    repo.getCustomerTopEventActions(customerUserId),
    repo.getCustomerLastCarSignals(customerUserId),
    repo.getCustomerLastEvents(customerUserId, { limit: 60 }),
  ]);

  return {
    customer: {
      id: base.id,
      fullName: base.full_name,
      phone: base.phone,
      block: base.block,
      buildingNumber: base.building_number,
      apartment: base.apartment,
      imageUrl: base.image_url,
      createdAt: base.created_at,
      analyticsConsent: {
        granted: base.analytics_consent_granted === true,
        version: base.analytics_consent_version || null,
        grantedAt: base.analytics_consent_granted_at || null,
      },
    },
    orderProfile: {
      ordersCount: Number(orders?.orders_count || 0),
      deliveredOrdersCount: Number(orders?.delivered_orders_count || 0),
      cancelledOrdersCount: Number(orders?.cancelled_orders_count || 0),
      totalSpent: Number(orders?.total_spent || 0),
      avgBasket: Number(orders?.avg_basket || 0),
      lastOrderAt: orders?.last_order_at || null,
      lastDeliveredAt: orders?.last_delivered_at || null,
      topMerchantTypes,
    },
    behaviorProfile: {
      topCategories,
      topActions,
      carSignals: extractTopCarSignals(carSignalsRows),
      lastEvents,
    },
  };
}

export async function listCustomersInsight(query) {
  const limit = clampInt(query?.limit, 1, 200, 30);
  const offset = clampInt(query?.offset, 0, 500000, 0);
  const search = trimOrNull(query?.search) || "";

  return repo.listCustomerInsightSummary({
    search,
    limit,
    offset,
  });
}
