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

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function toIsoOrNull(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function toCompactDateTime(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function extractTopCarSignals(rows = []) {
  const brandCount = new Map();
  const modelCount = new Map();
  const usageCount = new Map();
  const bodyTypeCount = new Map();
  const conditionCount = new Map();
  const budgetRanges = [];

  for (const row of rows) {
    const metadata = row.metadata && typeof row.metadata === "object" ? row.metadata : null;
    if (!metadata) continue;

    const brand = trimOrNull(metadata.brand);
    const model = trimOrNull(metadata.model);
    const usage = trimOrNull(metadata.usage);
    const bodyType = trimOrNull(metadata.bodyType);
    const condition = trimOrNull(metadata.condition);
    const budgetMin = Number(metadata.budgetMinM);
    const budgetMax = Number(metadata.budgetMaxM);

    if (brand) brandCount.set(brand, (brandCount.get(brand) || 0) + 1);
    if (model) modelCount.set(model, (modelCount.get(model) || 0) + 1);
    if (usage) usageCount.set(usage, (usageCount.get(usage) || 0) + 1);
    if (bodyType) bodyTypeCount.set(bodyType, (bodyTypeCount.get(bodyType) || 0) + 1);
    if (condition) {
      conditionCount.set(condition, (conditionCount.get(condition) || 0) + 1);
    }
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
    topBodyTypes: sorted(bodyTypeCount),
    conditionPreference: sorted(conditionCount),
    averageBudgetM: avgBudget,
    samplesCount: budgetRanges.length,
  };
}

const profileDomains = ["food", "style", "home", "electronics", "cars", "assistant"];

const profileDomainLabels = {
  food: "المطاعم والطعام",
  style: "الأزياء والموضة",
  home: "التسوق المنزلي",
  electronics: "الإلكترونيات",
  cars: "السيارات",
  assistant: "المساعد الذكي",
};

const domainKeywordMap = {
  food: [
    "restaurant",
    "food",
    "meal",
    "cafe",
    "coffee",
    "sweets",
    "مطعم",
    "مطاعم",
    "طعام",
    "وجبة",
    "قهوة",
    "حلويات",
    "معجنات",
    "مشروبات",
  ],
  style: [
    "fashion",
    "style",
    "women",
    "men",
    "shoes",
    "bags",
    "beauty",
    "أزياء",
    "موضة",
    "نسائي",
    "رجالي",
    "أحذية",
    "شنط",
    "عناية",
  ],
  home: [
    "market",
    "home",
    "grocery",
    "gift",
    "flower",
    "cleaning",
    "سوق",
    "أسواق",
    "خضار",
    "فواكه",
    "لحوم",
    "دواجن",
    "تنظيف",
    "منزل",
    "هدايا",
    "ورد",
    "مكتبة",
  ],
  electronics: [
    "electric",
    "electronics",
    "device",
    "phone",
    "كهربائيات",
    "أجهزة",
    "إلكترونيات",
    "هواتف",
  ],
  cars: [
    "car",
    "cars",
    "vehicle",
    "toyota",
    "hyundai",
    "kia",
    "سيارة",
    "سيارات",
    "مركبة",
    "موديل",
  ],
};

function detectDomainFromText(rawText) {
  const text = trimOrNull(rawText)?.toLowerCase();
  if (!text) return null;

  for (const [domain, words] of Object.entries(domainKeywordMap)) {
    if (words.some((word) => text.includes(word.toLowerCase()))) return domain;
  }
  return null;
}

function normalizeTerm(raw) {
  const value = trimOrNull(raw);
  if (!value) return null;
  const compact = value.replace(/\s+/g, " ").trim();
  if (compact.length < 2) return null;
  if (compact.length > 100) return compact.slice(0, 100);
  return compact;
}

function mergeCount(map, key, amount = 1) {
  if (!key) return;
  map.set(key, (map.get(key) || 0) + amount);
}

function mapEntries(map, limit = 8, keyName = "name", valueName = "count") {
  return [...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, count]) => ({ [keyName]: name, [valueName]: count }));
}

function extractSearchSignals(events = []) {
  const termCount = new Map();
  const domainCount = new Map();
  const termLastAt = new Map();
  const lastQueries = [];

  const queryKeys = [
    "query",
    "searchQuery",
    "search",
    "keyword",
    "seedQuery",
    "initialSearchQuery",
    "brand",
    "model",
    "freeText",
  ];

  for (const event of events) {
    const category = trimOrNull(event.category)?.toLowerCase();
    const action = trimOrNull(event.action)?.toLowerCase();
    const eventName = trimOrNull(event.event_name)?.toLowerCase();
    const metadata = event.metadata && typeof event.metadata === "object" ? event.metadata : {};
    const at = toIsoOrNull(event.created_at);

    const pathValue = trimOrNull(event.path);
    const pathQueryValues = [];
    if (pathValue && pathValue.includes("?")) {
      try {
        const qs = pathValue.split("?")[1];
        const params = new URLSearchParams(qs);
        for (const key of ["q", "query", "search", "brand", "model", "type"]) {
          const val = normalizeTerm(params.get(key));
          if (val) pathQueryValues.push(val);
        }
      } catch (_) {
        // ignore malformed query strings
      }
    }

    const terms = [];
    for (const key of queryKeys) {
      const term = normalizeTerm(metadata[key]);
      if (term) terms.push(term);
    }
    for (const term of pathQueryValues) {
      terms.push(term);
    }

    const isSearchLike =
      category === "cars" ||
      category === "merchants" ||
      category === "discovery" ||
      action === "search" ||
      action === "smart_search" ||
      Boolean(eventName && eventName.includes("search"));

    if (!isSearchLike && terms.length === 0) continue;

    const detectedFromMeta =
      detectDomainFromText(metadata.searchDomain) ||
      detectDomainFromText(metadata.category) ||
      detectDomainFromText(category);

    const candidateDomain = detectedFromMeta || detectDomainFromText(terms.join(" "));
    mergeCount(domainCount, candidateDomain || "general", 1);

    for (const term of terms) {
      mergeCount(termCount, term, 1);
      if (at) {
        const current = termLastAt.get(term);
        if (!current || current < at) termLastAt.set(term, at);
      }
      if (lastQueries.length < 16) {
        lastQueries.push({
          term,
          domain: candidateDomain || "general",
          at,
        });
      }
    }
  }

  const topTerms = [...termCount.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 12)
    .map(([term, count]) => ({
      term,
      count,
      lastAt: termLastAt.get(term) || null,
    }));

  return {
    totalSearchEvents: [...domainCount.values()].reduce((sum, v) => sum + v, 0),
    topTerms,
    topDomains: mapEntries(domainCount, 8, "domain", "count"),
    recentQueries: lastQueries,
  };
}

function buildAffinityProfile({
  topCategories = [],
  topActions = [],
  topMerchantTypes = [],
  orderCategories = [],
  searchSignals = null,
  aiPreferenceJson = null,
}) {
  const score = {
    food: 0,
    style: 0,
    home: 0,
    electronics: 0,
    cars: 0,
    assistant: 0,
  };

  const boostByText = (text, amount = 1) => {
    const domain = detectDomainFromText(text);
    if (domain && score[domain] !== undefined) score[domain] += amount;
  };

  for (const row of topMerchantTypes) {
    const type = trimOrNull(row.type)?.toLowerCase();
    const c = toNumber(row.orders_count, 0);
    if (type === "restaurant") score.food += c * 6;
    if (type === "market") {
      score.home += c * 4;
      score.style += c * 2;
      score.electronics += c * 2;
      score.cars += c * 2;
    }
  }

  for (const row of topCategories) {
    const category = trimOrNull(row.category)?.toLowerCase();
    const c = toNumber(row.events_count, 0);
    if (!category) continue;
    if (category === "assistant") score.assistant += c * 5;
    if (category === "cars") score.cars += c * 6;
    if (category === "orders") {
      score.food += c * 2;
      score.home += c * 2;
    }
    boostByText(category, c * 3);
  }

  for (const row of topActions) {
    const name = trimOrNull(row.event_name)?.toLowerCase();
    const category = trimOrNull(row.category)?.toLowerCase();
    const c = toNumber(row.events_count, 0);
    if (name?.includes("assistant") || category === "assistant") {
      score.assistant += c * 2;
    }
    if (name?.includes("cars") || category === "cars") score.cars += c * 2;
    boostByText(`${name || ""} ${category || ""}`, c * 2);
  }

  for (const row of orderCategories) {
    const name = trimOrNull(row.category_name);
    const c = toNumber(row.items_count, 0);
    boostByText(name, c * 1.3);
  }

  for (const row of searchSignals?.topTerms || []) {
    boostByText(row.term, toNumber(row.count, 0) * 2);
  }
  for (const row of searchSignals?.topDomains || []) {
    const domain = trimOrNull(row.domain)?.toLowerCase();
    const c = toNumber(row.count, 0);
    if (domain && score[domain] !== undefined) score[domain] += c * 3;
  }

  const homePrefs = aiPreferenceJson?.homePreferences;
  const interests = Array.isArray(homePrefs?.interests)
    ? homePrefs.interests.map((v) => String(v || "").toLowerCase())
    : [];
  if (interests.length) {
    for (const key of interests) {
      boostByText(key, 8);
    }
  }

  const maxValue = Math.max(...Object.values(score), 1);
  const normalized = profileDomains.map((domain) => ({
    domain,
    label: profileDomainLabels[domain] || domain,
    rawScore: Number(score[domain] || 0),
    score: Math.round(((score[domain] || 0) / maxValue) * 100),
  }));

  normalized.sort((a, b) => b.score - a.score);

  return {
    dominantDomain: normalized[0]?.domain || "food",
    dominantLabel: normalized[0]?.label || profileDomainLabels.food,
    scores: normalized,
  };
}

function buildActivityPattern(activitySummary, topHours) {
  const eventsCount = toNumber(activitySummary?.events_count);
  const events30d = toNumber(activitySummary?.events_30d);
  const events7d = toNumber(activitySummary?.events_7d);
  const activeDays30d = toNumber(activitySummary?.active_days_30d);
  const averagePerActiveDay = activeDays30d > 0 ? events30d / activeDays30d : 0;
  const averagePerDay7d = 7 > 0 ? events7d / 7 : 0;

  return {
    eventsCount,
    events30d,
    events7d,
    activeDays30d,
    activeDaysTotal: toNumber(activitySummary?.active_days_count),
    firstEventAt: toIsoOrNull(activitySummary?.first_event_at),
    lastEventAt: toIsoOrNull(activitySummary?.last_event_at),
    averageEventsPerActiveDay30d: Number(averagePerActiveDay.toFixed(2)),
    averageEventsPerDay7d: Number(averagePerDay7d.toFixed(2)),
    topHours: (topHours || []).map((row) => ({
      hour: toNumber(row.hour),
      eventsCount: toNumber(row.events_count),
    })),
  };
}

function buildPersonaSummary({
  orders,
  activityPattern,
  affinity,
  searchSignals,
  favoritesSummary,
}) {
  const avgBasket = toNumber(orders?.avg_basket);
  const ordersCount = toNumber(orders?.orders_count);
  const events30d = toNumber(activityPattern?.events30d);
  const favoritesCount = toNumber(
    favoritesSummary?.favoritesCount ?? favoritesSummary?.favorites_count
  );
  const totalSearchEvents = toNumber(searchSignals?.totalSearchEvents);

  const spendingTier =
    avgBasket >= 40000 ? "مرتفع" : avgBasket >= 18000 ? "متوسط" : "اقتصادي";

  const engagementLevel =
    events30d >= 140 ? "مرتفع جدا" : events30d >= 70 ? "مرتفع" : events30d >= 25 ? "متوسط" : "منخفض";

  const decisionStyle =
    totalSearchEvents >= 45
      ? "يبحث ويقارن قبل الشراء"
      : favoritesCount >= 12
      ? "يعتمد على العناصر المفضلة"
      : ordersCount >= 20
      ? "عميل متكرر وواضح التوجه"
      : "تجربة واستكشاف";

  const likelyInterests = affinity?.scores
    ? affinity.scores.filter((item) => item.score >= 35).slice(0, 3).map((item) => item.label)
    : [];

  const campaignHints = [];
  if (spendingTier === "اقتصادي") campaignHints.push("عروض سعرية وخصومات مباشرة");
  if (spendingTier === "متوسط") campaignHints.push("عروض قيمة مقابل السعر");
  if (spendingTier === "مرتفع") campaignHints.push("خيارات مميزة وتجارب أعلى جودة");
  if (decisionStyle.includes("يقارن")) campaignHints.push("إظهار مقارنة سريعة بين الخيارات");
  if (likelyInterests.length) campaignHints.push(`تركيز على: ${likelyInterests.join("، ")}`);

  return {
    spendingTier,
    engagementLevel,
    decisionStyle,
    likelyInterests,
    campaignHints,
  };
}

function mapTopRows(rows, nameKey, countKey) {
  return (rows || []).map((row) => ({
    [nameKey]: row?.[nameKey] ?? row?.name ?? null,
    [countKey]: toNumber(row?.[countKey]),
    lastAt: toIsoOrNull(row?.last_at),
  }));
}

function mapTopMerchants(rows = []) {
  return rows.map((row) => ({
    merchantId: toNumber(row.merchant_id),
    merchantName: row.merchant_name || null,
    merchantType: row.type || null,
    ordersCount: toNumber(row.orders_count),
    totalSpent: toNumber(row.total_spent),
    lastOrderAt: toIsoOrNull(row.last_order_at),
  }));
}

function mapTopProducts(rows = []) {
  return rows.map((row) => ({
    productId: toNumber(row.product_id),
    productName: row.product_name || null,
    merchantId: toNumber(row.merchant_id),
    merchantName: row.merchant_name || null,
    merchantType: row.merchant_type || null,
    unitsCount: toNumber(row.units_count),
    totalSpent: toNumber(row.total_spent),
    lastOrderAt: toIsoOrNull(row.last_order_at),
  }));
}

function mapOrderCategories(rows = []) {
  return rows.map((row) => ({
    categoryName: row.category_name || "general",
    ordersCount: toNumber(row.orders_count),
    itemsCount: toNumber(row.items_count),
    totalSpent: toNumber(row.total_spent),
    lastOrderAt: toIsoOrNull(row.last_order_at),
  }));
}

function mapFavoriteSummary(favorites) {
  const summary = favorites?.summary || {};
  return {
    favoritesCount: toNumber(summary?.favorites_count),
    restaurantFavoritesCount: toNumber(summary?.restaurant_favorites_count),
    marketFavoritesCount: toNumber(summary?.market_favorites_count),
    lastFavoriteAt: toIsoOrNull(summary?.last_favorite_at),
    recentFavorites: (favorites?.items || []).map((row) => ({
      productId: toNumber(row.product_id),
      productName: row.product_name || null,
      merchantId: toNumber(row.merchant_id),
      merchantName: row.merchant_name || null,
      merchantType: row.merchant_type || null,
      effectivePrice: toNumber(row.effective_price),
      favoritedAt: toIsoOrNull(row.created_at),
    })),
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
    topMerchantsRows,
    topProductsRows,
    topOrderCategoriesRows,
    favorites,
    activitySummary,
    hourlyActivity,
    eventsForAnalysis,
    aiProfile,
    lastEvents,
  ] = await Promise.all([
    repo.getCustomerOrderStats(customerUserId),
    repo.getCustomerTopMerchantTypes(customerUserId),
    repo.getCustomerTopActivityCategories(customerUserId),
    repo.getCustomerTopEventActions(customerUserId),
    repo.getCustomerLastCarSignals(customerUserId),
    repo.getCustomerTopMerchants(customerUserId),
    repo.getCustomerTopProducts(customerUserId),
    repo.getCustomerTopOrderCategories(customerUserId),
    repo.getCustomerFavoritesSummary(customerUserId),
    repo.getCustomerActivitySummary(customerUserId),
    repo.getCustomerHourlyActivity(customerUserId),
    repo.getCustomerEventsForAnalysis(customerUserId),
    repo.getCustomerAiPreferenceProfile(customerUserId),
    repo.getCustomerLastEvents(customerUserId, { limit: 60 }),
  ]);

  const searchSignals = extractSearchSignals(eventsForAnalysis);
  const affinity = buildAffinityProfile({
    topCategories,
    topActions,
    topMerchantTypes,
    orderCategories: topOrderCategoriesRows,
    searchSignals,
    aiPreferenceJson: aiProfile?.preference_json || null,
  });
  const activityPattern = buildActivityPattern(activitySummary, hourlyActivity);
  const favoritesSummary = mapFavoriteSummary(favorites);
  const persona = buildPersonaSummary({
    orders,
    activityPattern,
    affinity,
    searchSignals,
    favoritesSummary,
  });

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
      profileLastUpdatedAt: toCompactDateTime(aiProfile?.updated_at),
    },
    orderProfile: {
      ordersCount: toNumber(orders?.orders_count || 0),
      deliveredOrdersCount: toNumber(orders?.delivered_orders_count || 0),
      cancelledOrdersCount: toNumber(orders?.cancelled_orders_count || 0),
      totalSpent: toNumber(orders?.total_spent || 0),
      avgBasket: toNumber(orders?.avg_basket || 0),
      lastOrderAt: toIsoOrNull(orders?.last_order_at),
      lastDeliveredAt: toIsoOrNull(orders?.last_delivered_at),
      topMerchantTypes: (topMerchantTypes || []).map((row) => ({
        type: row.type || "unknown",
        ordersCount: toNumber(row.orders_count),
        totalSpent: toNumber(row.total_spent),
      })),
      topMerchants: mapTopMerchants(topMerchantsRows),
      topProducts: mapTopProducts(topProductsRows),
      topOrderCategories: mapOrderCategories(topOrderCategoriesRows),
    },
    behaviorProfile: {
      topCategories: mapTopRows(topCategories, "category", "events_count"),
      topActions: (topActions || []).map((row) => ({
        eventName: row.event_name || null,
        category: row.category || null,
        eventsCount: toNumber(row.events_count),
        lastAt: toIsoOrNull(row.last_at),
      })),
      searchSignals,
      affinity,
      activityPattern,
      favoritesSummary,
      persona,
      aiProfile: {
        hasProfile: !!aiProfile,
        lastSummary: aiProfile?.last_summary || null,
        homePreferences:
          aiProfile?.preference_json && typeof aiProfile.preference_json === "object"
            ? aiProfile.preference_json.homePreferences || null
            : null,
      },
      carSignals: extractTopCarSignals(carSignalsRows),
      lastEvents: (lastEvents || []).map((row) => ({
        id: toNumber(row.id),
        eventName: row.event_name || null,
        category: row.category || null,
        action: row.action || null,
        source: row.source || null,
        path: row.path || null,
        method: row.method || null,
        entityType: row.entity_type || null,
        entityId: row.entity_id == null ? null : toNumber(row.entity_id),
        statusCode: row.status_code == null ? null : toNumber(row.status_code),
        metadata: row.metadata && typeof row.metadata === "object" ? row.metadata : null,
        createdAt: toIsoOrNull(row.created_at),
      })),
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
