/**
 * Mimo's map of the whole app: every store (with its section, rating, orders
 * and area) and every service. The phone caches it and answers from it
 * instantly — no AI involved — and uses it to walk the user to a place.
 * Built from our own tables, cached in memory for a minute.
 */

const TTL_MS = 60 * 1000;

const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};
/** 0 in these columns means "unknown", not a real zero. */
const pos = (v) => {
  const n = num(v);
  return n && n !== 0 ? n : null;
};
const str = (v, max = 160) => {
  const s = String(v ?? "").replace(/\s+/g, " ").trim();
  return s ? s.slice(0, max) : null;
};

export function createDefaultDirectoryDeps() {
  return {
    async stores() {
      const m = await import("../merchants/merchants.repo.js");
      return m.getAllMerchants(null, null, {});
    },
    async services() {
      const m = await import("../services/services.repo.js");
      return m.searchPublicOfferings({ limit: 100 }, {});
    },
  };
}

export function mapStore(m) {
  const subs = Array.isArray(m.discovery_subcategories) ? m.discovery_subcategories : [];
  return {
    id: Number(m.id),
    name: str(m.name, 120),
    type: str(m.type, 30) || "market",
    activityType: str(m.activity_type, 60) || "",
    subcategories: subs.map((s) => str(typeof s === "string" ? s : s?.code || s?.name, 60)).filter(Boolean).slice(0, 8),
    pharmacy: m.supports_pharmacy_workflow === true,
    rating: pos(m.avg_merchant_rating),
    ratingCount: num(m.rating_count) || 0,
    orders: num(m.completed_orders_count) || 0,
    isOpen: m.is_open !== false,
    offer: m.has_discount_offer === true,
    freeDelivery: m.has_free_delivery_offer === true,
    area: str(m.service_area_note, 120),
    lat: pos(m.latitude),
    lng: pos(m.longitude),
    logoUrl: str(m.logo_url || m.image_url, 400),
    tagline: str(m.tagline, 120),
    etaMin: pos(m.delivery_eta_min_minutes),
    etaMax: pos(m.delivery_eta_max_minutes),
  };
}

export function mapService(o) {
  const p = o.provider || {};
  return {
    id: Number(o.id),
    name: str(o.name, 120),
    category: str(o.mainCategoryName, 60),
    subcategory: str(o.subcategoryName, 60),
    provider: str(p.businessName || p.business_name || o.providerBusinessName, 120),
    area: str([p.area, p.city].filter(Boolean).join("، "), 120),
    rating: pos(o.ratingAvg ?? p.ratingAvg),
    ratingCount: num(o.ratingCount ?? p.ratingCount) || 0,
    orders: num(o.completedOrdersCount) || 0,
    startsFrom: num(o.startsFromPrice),
    paused: o.isTemporarilyPaused === true,
  };
}

let cache = null;

/** The whole directory (cached TTL_MS). */
export async function loadDirectory(deps = createDefaultDirectoryDeps(), { now = Date.now(), force = false } = {}) {
  if (!force && cache && now - cache.at < TTL_MS) return cache.value;
  const [stores, services] = await Promise.all([
    deps.stores().catch(() => []),
    deps.services().catch(() => []),
  ]);
  const value = {
    generatedAt: new Date(now).toISOString(),
    stores: (stores || []).map(mapStore).filter((s) => s.id && s.name),
    services: (services || []).map(mapService).filter((s) => s.id && s.name && !s.paused),
  };
  cache = { at: now, value };
  return value;
}

/** Test seam. */
export function __resetDirectoryCache() {
  cache = null;
}
