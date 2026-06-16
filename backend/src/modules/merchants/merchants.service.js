import { hashPin } from "../../shared/utils/hash.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import * as repo from "./merchants.repo.js";
import {
  applyMerchantOfferPricing,
} from "../owner/merchant-offers.logic.js";
import {
  listLatestEligibleOffersByProductIds,
} from "../owner/merchant-offers.repo.js";
import { AppError } from "../../shared/utils/errors.js";
import { env } from "../../config/env.js";
import {
  buildMerchantCapabilities,
  inferActivityTypeFromMerchantType,
  listActivityRegistry,
  listDiscoveryOptions as listActivityDiscoveryOptions,
  normalizeActivityType as normalizeRegistryActivityType,
  normalizeDiscoverySubcategoryList as normalizeRegistryDiscoverySubcategoryList,
  normalizeDiscoverySubcategory as normalizeRegistryDiscoverySubcategory,
  requireActivityConfig,
  requireValidDiscoverySelection,
} from "./store-activity.registry.js";

const merchantBrowseInflight = new Map();

/**
 * Purpose:
 * منطق المتاجر العام من منظور التصفح والإدارة العامة: إنشاء متجر، عرض
 * المتاجر العامة، المنتجات، ولوحة الإعلانات.
 *
 * Used by:
 * - `merchants.controller.js`
 * - شاشات التصفح والـ hubs في Flutter
 */

function normalizeOptional(v) {
  if (v === undefined || v === null) return null;
  const out = String(v).trim();
  return out.length ? out : null;
}

function toPositiveIntOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function merchantBrowseInflightKey({
  type,
  search,
  activityType,
  discoverySubcategory,
}) {
  return JSON.stringify([
    String(type || "all"),
    String(search || ""),
    String(activityType || ""),
    String(discoverySubcategory || ""),
  ]);
}

async function runMerchantBrowseSingleFlight(cacheContext, loader) {
  const key = merchantBrowseInflightKey(cacheContext);
  const existing = merchantBrowseInflight.get(key);
  if (existing) return existing;

  const promise = (async () => {
    try {
      return await loader();
    } finally {
      merchantBrowseInflight.delete(key);
    }
  })();
  merchantBrowseInflight.set(key, promise);
  return promise;
}

function toBrowseMerchantPayload(row) {
  return {
    id: Number(row.id || 0),
    name: String(row.name || ""),
    type: normalizePublicMerchantType(row.type) || "market",
    activityType:
      normalizeRegistryActivityType(row.activityType ?? row.activity_type) ||
      "market",
    description: normalizeOptional(row.description),
    phone: normalizeOptional(row.phone),
    imageUrl: normalizeOptional(row.imageUrl ?? row.image_url),
    tagline: normalizeOptional(row.tagline),
    workingHours: normalizeOptional(row.workingHours ?? row.working_hours),
    avgMerchantRating: Number(row.avgMerchantRating ?? row.avg_merchant_rating ?? 0),
    ratingCount: Math.max(0, Number(row.ratingCount ?? row.rating_count ?? 0)),
    isOpen: row.isOpen === true || row.is_open === true,
    hasDiscountOffer:
      row.hasDiscountOffer === true || row.has_discount_offer === true,
    hasFreeDeliveryOffer:
      row.hasFreeDeliveryOffer === true || row.has_free_delivery_offer === true,
    supportsPharmacyWorkflow:
      row.supportsPharmacyWorkflow === true ||
      row.supports_pharmacy_workflow === true,
    smartRankScore: Number(row.smartRankScore ?? row.smart_rank_score ?? 0),
  };
}

/**
 * ينشئ متجراً جديداً إما بربطه بمالك موجود أو بإنشاء مالك جديد معه.
 *
 * Critical notes:
 * - هذه الدالة حساسة لتعارضات phone/owner uniqueness.
 */
export async function createMerchant(dto, approvedByUserId) {
  const ownerUserId = toPositiveIntOrNull(dto.ownerUserId);
  const hasOwnerUserId = ownerUserId !== null;
  const hasOwnerObject = dto.owner && typeof dto.owner === "object";

  if (!hasOwnerUserId && !hasOwnerObject) {
    const err = new Error("OWNER_REQUIRED");
    err.status = 400;
    throw err;
  }

  if (hasOwnerUserId && hasOwnerObject) {
    const err = new Error("OWNER_CONFLICT");
    err.status = 400;
    throw err;
  }

  const requestedActivityType = normalizeRegistryActivityType(
    dto.activityType,
    inferActivityTypeFromMerchantType(dto.type)
  );
  const activityConfig = await requireActivityConfig(requestedActivityType);
  if (String(activityConfig.baseType || "").trim() !== String(dto.type || "").trim()) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { type: "INVALID_ACTIVITY_BASE_TYPE" } },
    });
  }

  const discoverySelection = await requireValidDiscoverySelection(
    activityConfig.activityType,
    {
      discoverySubcategory: dto.discoverySubcategory,
      discoverySubcategories: dto.discoverySubcategories,
      discoverySelectAll: dto.discoverySelectAll === true,
    }
  );
  const capabilities = buildMerchantCapabilities(activityConfig, {
    serviceFlags: dto.serviceFlags,
    badges: dto.badges,
    supportsChat: dto.supportsChat,
    supportsAttachments: dto.supportsAttachments,
    supportsPharmacyWorkflow: dto.supportsPharmacyWorkflow,
  });

  const merchant = {
    name: dto.name.trim(),
    type: dto.type,
    activityType: activityConfig.activityType,
    discoverySubcategory: discoverySelection.legacyDiscoverySubcategory || null,
    discoverySubcategories: discoverySelection.discoverySubcategories,
    discoverySelectAll: discoverySelection.discoverySelectAll === true,
    description: normalizeOptional(dto.description),
    phone: normalizeOptional(dto.phone),
    imageUrl: normalizeOptional(dto.imageUrl),
    serviceFlags: capabilities.serviceFlags,
    badges: capabilities.badges,
    supportsChat: capabilities.supportsChat,
    supportsAttachments: capabilities.supportsAttachments,
    supportsPharmacyWorkflow: capabilities.supportsPharmacyWorkflow,
  };

  let ownerToCreate = null;
  let ownerPinHash = null;
  let createMerchantOperation = () =>
    repo.createMerchantWithOwnerLink({
      merchant,
      approvedByUserId,
      ownerUserId,
      ownerToCreate,
      ownerPinHash,
    });

  if (!hasOwnerUserId && hasOwnerObject) {
    const ownerFullName = dto.owner.fullName.trim();
    const ownerPhone = dto.owner.phone.trim();
    ownerToCreate = {
      fullName: ownerFullName,
      username: null,
      phone: ownerPhone,
      block: dto.owner.block.trim(),
      buildingNumber: dto.owner.buildingNumber.trim(),
      apartment: dto.owner.apartment.trim(),
      imageUrl: normalizeOptional(dto.owner.imageUrl),
    };
    ownerPinHash = await hashPin(dto.owner.pin);
    createMerchantOperation = () =>
      runWithGeneratedAppUserUsername({
        fullName: ownerFullName,
        phone: ownerPhone,
        execute: (username) =>
          repo.createMerchantWithOwnerLink({
            merchant,
            approvedByUserId,
            ownerUserId,
            ownerToCreate: {
              ...ownerToCreate,
              username,
            },
            ownerPinHash,
          }),
      });
  }

  try {
    const created = await createMerchantOperation();
    await repo.ensureMerchantDefaultInternalCategories(created.id);
    return created;
  } catch (e) {
    if (e?.code === "23505") {
      const constraint = String(e.constraint || "");
      if (constraint.includes("app_user_phone")) {
        const err = new Error("PHONE_EXISTS");
        err.status = 409;
        throw err;
      }
      if (constraint.includes("merchant_owner_user_id")) {
        const err = new Error("OWNER_ALREADY_HAS_MERCHANT");
        err.status = 409;
        throw err;
      }
    }
    throw e;
  }
}

/**
 * يعيد قائمة المتاجر العامة مع تطبيع نوع التاجر المعروض للواجهة.
 */
export async function listMerchants(type, search, options = {}) {
  const requestedType = normalizePublicMerchantType(type);
  const requestedActivityType = normalizeRegistryActivityType(options.activityType);
  const requestedDiscoverySubcategory = normalizeRegistryDiscoverySubcategory(
    options.discoverySubcategory
  );
  const cacheContext = {
    type: requestedType,
    search:
      typeof search === "string" && search.trim().length ? search.trim() : null,
    activityType: requestedActivityType,
    discoverySubcategory: requestedDiscoverySubcategory,
  };
  const cached = await repo.getCachedMerchantBrowseList(cacheContext);
  if (Array.isArray(cached)) {
    return cached;
  }
  return runMerchantBrowseSingleFlight(cacheContext, async () => {
    const recached = await repo.getCachedMerchantBrowseList(cacheContext);
    if (Array.isArray(recached)) {
      return recached;
    }

    const rows = await repo.getAllMerchants(requestedType, search, {
      activityType: requestedActivityType,
      discoverySubcategory: requestedDiscoverySubcategory,
    });

    const mapped = rows.map((row) => ({
      ...row,
      type: normalizePublicMerchantType(row.type) || "market",
      activityType: normalizeRegistryActivityType(row.activity_type) || "market",
      discoverySubcategory: normalizeRegistryDiscoverySubcategory(
        row.discovery_subcategory
      ),
      discoverySubcategories: normalizeRegistryDiscoverySubcategoryList(
        row.discovery_subcategories
      ),
      discoverySelectAll: row.discovery_select_all === true,
      serviceFlags:
        row.service_flags_json && typeof row.service_flags_json === "object"
          ? row.service_flags_json
          : {},
      badges: Array.isArray(row.badges_json) ? row.badges_json : [],
      supportsChat: row.supports_chat === true,
      supportsAttachments: row.supports_attachments === true,
      supportsPharmacyWorkflow: row.supports_pharmacy_workflow === true,
    }));

    if (mapped.length <= 1) {
      const payload = mapped.map(toBrowseMerchantPayload);
      await repo.setCachedMerchantBrowseList(cacheContext, payload);
      return payload;
    }

    const prices = mapped
      .map((row) => Number(row.avg_menu_price || 0))
      .filter((value) => Number.isFinite(value) && value > 0);
    const minPrice = prices.length ? Math.min(...prices) : 0;
    const maxPrice = prices.length ? Math.max(...prices) : 0;
    const priceRange = Math.max(1, maxPrice - minPrice);
    const globalRatingValues = mapped
      .map((row) => Number(row.avg_merchant_rating || 0))
      .filter((value) => Number.isFinite(value) && value > 0);
    const globalRating =
      globalRatingValues.length > 0
        ? globalRatingValues.reduce((sum, value) => sum + value, 0) /
          globalRatingValues.length
        : 3.8;

    const ranked = mapped
      .map((row) => {
        const ratingCount = Math.max(0, Number(row.rating_count || 0));
        const avgRating = Math.max(
          0,
          Math.min(5, Number(row.avg_merchant_rating || 0))
        );
        const avgPrice = Math.max(0, Number(row.avg_menu_price || 0));
        const completedOrders = Math.max(
          0,
          Number(row.completed_orders_count || 0)
        );

        const bayesianRating =
          (avgRating * ratingCount + globalRating * 8) /
          Math.max(1, ratingCount + 8);
        const qualityScore = bayesianRating / 5;
        const affordabilityScore =
          avgPrice > 0 && maxPrice > minPrice
            ? Math.max(0, Math.min(1, 1 - (avgPrice - minPrice) / priceRange))
            : 0.5;
        const reliabilityScore = Math.max(
          0,
          Math.min(1, Math.log1p(completedOrders) / Math.log1p(240))
        );

        const smartScore =
          qualityScore * 0.55 +
          affordabilityScore * 0.30 +
          reliabilityScore * 0.15;
        return {
          ...row,
          smart_rank_score: Number(smartScore.toFixed(6)),
        };
      })
      .sort((a, b) => {
        const scoreDiff =
          Number(b.smart_rank_score || 0) - Number(a.smart_rank_score || 0);
        if (scoreDiff !== 0) return scoreDiff;
        const ratingDiff =
          Number(b.avg_merchant_rating || 0) -
          Number(a.avg_merchant_rating || 0);
        if (ratingDiff !== 0) return ratingDiff;
        const priceDiff =
          Number(a.avg_menu_price || 0) - Number(b.avg_menu_price || 0);
        if (priceDiff !== 0) return priceDiff;
        return Number(b.id || 0) - Number(a.id || 0);
      });
    const payload = ranked.map(toBrowseMerchantPayload);
    await repo.setCachedMerchantBrowseList(cacheContext, payload);
    return payload;
  });
}

/**
 * يعيد المنتجات العامة لمتجر واحد مع دمج العروض النشطة في السعر الظاهر.
 */
export async function listMerchantProducts(merchantId, { limit, offset } = {}) {
  const rows = await repo.getPublicMerchantProducts(merchantId, { limit, offset });
  if (!rows.length) return rows;
  const activeOffers = await listLatestEligibleOffersByProductIds({
    merchantId: Number(merchantId),
    productIds: rows.map((row) => Number(row.id)),
  });
  const offerMap = new Map(
    activeOffers.map((offer) => [String(offer.product_id), offer])
  );

  return rows.map((row) => {
    const activeOffer = offerMap.get(String(row.id)) || null;
    if (!activeOffer) return row;

    const pricing = applyMerchantOfferPricing({
      baseUnitPrice: Number(row.price),
      quantity: 1,
      offer: activeOffer,
      fallbackDiscountedPrice: null,
    });

    return {
      ...row,
      discounted_price:
        activeOffer.offer_type === "buy_x_get_y"
          ? null
          : pricing.displayDiscountedUnitPrice,
      offer_label: pricing.offerLabel,
      active_offer_id: Number(activeOffer.id),
      active_offer_type: activeOffer.offer_type,
      active_offer_title: activeOffer.title,
      active_offer_discount_value:
        activeOffer.discount_value == null
          ? null
          : Number(activeOffer.discount_value),
      active_offer_buy_quantity:
        activeOffer.buy_quantity == null
          ? null
          : Number(activeOffer.buy_quantity),
      active_offer_get_quantity:
        activeOffer.get_quantity == null
          ? null
          : Number(activeOffer.get_quantity),
    };
  });
}

export async function listMerchantCategories(merchantId) {
  return repo.getPublicMerchantCategories(merchantId);
}

function mapPublicMerchantRow(row) {
  return {
    ...row,
    id: Number(row.id),
    type: normalizePublicMerchantType(row.type) || "market",
    activityType: normalizeRegistryActivityType(row.activity_type) || "market",
    discoverySubcategory: normalizeRegistryDiscoverySubcategory(
      row.discovery_subcategory
    ),
    discoverySubcategories: normalizeRegistryDiscoverySubcategoryList(
      row.discovery_subcategories
    ),
    discoverySelectAll: row.discovery_select_all === true,
    serviceFlags:
      row.service_flags_json && typeof row.service_flags_json === "object"
        ? row.service_flags_json
        : {},
    badges: Array.isArray(row.badges_json) ? row.badges_json : [],
    supportsChat: row.supports_chat === true,
    supportsAttachments: row.supports_attachments === true,
    supportsPharmacyWorkflow: row.supports_pharmacy_workflow === true,
    hasDiscountOffer: row.has_discount_offer === true,
    hasFreeDeliveryOffer: row.has_free_delivery_offer === true,
    avgMerchantRating: Number(row.avg_merchant_rating || 0),
    ratingCount: Number(row.rating_count || 0),
    latitude:
      row.latitude === null || row.latitude === undefined
        ? null
        : Number(row.latitude),
    longitude:
      row.longitude === null || row.longitude === undefined
        ? null
        : Number(row.longitude),
    distanceKm:
      row.distance_km === null || row.distance_km === undefined
        ? null
        : Number(row.distance_km),
  };
}

export async function getPublicMerchantSummary(merchantId) {
  const row = await repo.getPublicMerchantById(merchantId);
  if (!row) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }
  return mapPublicMerchantRow(row);
}

export async function listNearbyMerchants({
  latitude,
  longitude,
  radiusKm,
  limit,
  type,
}) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    throw new AppError("LATITUDE_INVALID", { status: 400 });
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    throw new AppError("LONGITUDE_INVALID", { status: 400 });
  }

  const radius = Number.isFinite(Number(radiusKm))
    ? Number(radiusKm)
    : Number(env.nearbyStoresRadiusKmDefault || 10);
  const maxItems = Number.isFinite(Number(limit))
    ? Math.trunc(Number(limit))
    : Number(env.nearbyStoresLimitDefault || 40);

  const rows = await repo.getNearbyPublicMerchants({
    latitude: lat,
    longitude: lng,
    radiusKm: radius,
    limit: maxItems,
    type: normalizePublicMerchantType(type),
  });
  return rows.map(mapPublicMerchantRow);
}

/**
 * يعيد بطاقات لوحة الإعلانات العامة المعروضة في الواجهة.
 */
export async function listPublicAdBoard(type) {
  const normalizedType = normalizeType(type);
  const rows = await repo.getPublicAdBoardItems({ type: normalizedType });
  return rows.map((row) => ({
    id: Number(row.id),
    title: row.title,
    subtitle: row.subtitle,
    imageUrl: row.image_url || row.merchant_image_url || null,
    badgeLabel: row.badge_label || null,
    ctaLabel: row.cta_label || null,
    type: row.cta_target_type || "none",
    targetId: row.target_id
      ? Number(row.target_id)
      : row.merchant_id
      ? Number(row.merchant_id)
      : null,
    targetRoute: row.target_route || null,
    promoCode: row.promo_code || null,
    category: row.category || null,
    externalLink: row.external_link || null,
    ctaTargetType: row.cta_target_type || "none",
    ctaTargetValue: row.cta_target_value || null,
    merchantId: row.merchant_id ? Number(row.merchant_id) : null,
    merchantName: row.merchant_name || null,
    merchantType: row.merchant_type || null,
    merchantIsOpen: row.merchant_is_open === true,
    priority: Number(row.priority || 0),
    startsAt: row.starts_at ? new Date(row.starts_at).toISOString() : null,
    endsAt: row.ends_at ? new Date(row.ends_at).toISOString() : null,
  }));
}

export async function listStoreActivities() {
  const rows = await listActivityRegistry({ includeInactive: false });
  return rows.map((item) => ({
    activityType: item.activityType,
    baseType: item.baseType,
    displayNameEn: item.displayNameEn,
    displayNameAr: item.displayNameAr,
    hasDiscoverySubcategories: item.hasDiscoverySubcategories,
    supportsChat: item.supportsChat,
    supportsAttachments: item.supportsAttachments,
    supportsPharmacyWorkflow: item.supportsPharmacyWorkflow,
    internalCategoryMode: item.internalCategoryMode,
    defaultServiceFlags: item.defaultServiceFlags,
    defaultBadges: item.defaultBadges,
  }));
}

export async function listStoreDiscoveryOptions(activityType) {
  const options = await listActivityDiscoveryOptions(activityType);
  return options.map((item) => ({
    id: item.id,
    activityType: item.activityType,
    code: item.code,
    labelEn: item.labelEn,
    labelAr: item.labelAr,
    orderIndex: item.orderIndex,
    metadata: item.metadata,
  }));
}

const supportedMerchantTypes = new Set(["restaurant", "market"]);

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(value, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value));
}

function normalize(value, min, max, fallback = 0.5) {
  if (!Number.isFinite(value)) return fallback;
  if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) return fallback;
  return clamp((value - min) / (max - min), 0, 1);
}

function normalizeInverse(value, min, max, fallback = 0.5) {
  if (!Number.isFinite(value)) return fallback;
  if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) return fallback;
  return clamp((max - value) / (max - min), 0, 1);
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = clamp(p, 0, 1) * (sorted.length - 1);
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sorted[lower];
  const ratio = index - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * ratio;
}

function round(value, digits = 2) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Number(n.toFixed(digits));
}

function toIsoOrNull(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function spendingBand(avgOrderValue, p35, p70) {
  if (avgOrderValue <= 0) return "new_customer";
  if (p70 <= 0) {
    if (avgOrderValue < 15000) return "budget";
    if (avgOrderValue < 35000) return "balanced";
    return "premium";
  }
  if (avgOrderValue <= p35) return "budget";
  if (avgOrderValue <= p70) return "balanced";
  return "premium";
}

function classifyPriceTier(value, p33, p66) {
  if (value <= 0) return "unknown";
  if (value <= p33) return "budget";
  if (value <= p66) return "mid";
  return "premium";
}

function typeWeights(type) {
  if (type === "market") {
    return {
      speed: 0.20,
      quality: 0.24,
      value: 0.26,
      offers: 0.16,
      popularity: 0.14,
    };
  }
  return {
    speed: 0.25,
    quality: 0.28,
    value: 0.21,
    offers: 0.15,
    popularity: 0.11,
  };
}

function sortByScore(rows, getter, limit = 8, minScore = 0) {
  return rows
    .filter((row) => getter(row) > minScore)
    .sort((a, b) => {
      const diff = getter(b) - getter(a);
      if (diff !== 0) return diff;
      return (a.name || "").localeCompare(b.name || "");
    })
    .slice(0, limit);
}

function normalizeType(type) {
  if (!type) return null;
  const out = String(type).trim();
  if (!out) return null;
  if (!supportedMerchantTypes.has(out)) {
    const err = new Error("INVALID_MERCHANT_TYPE");
    err.status = 400;
    throw err;
  }
  return out;
}

function normalizePublicMerchantType(type) {
  if (type == null) return null;
  const raw = String(type).trim().toLowerCase();
  if (!raw) return null;

  if (raw === "restaurant") return "restaurant";
  if (raw === "market") return "market";

  if (
    [
      "restaurants",
      "food",
      "foods",
      "sweets",
      "dessert",
      "cafe",
      "coffee",
      "bakery",
      "pastry",
    ].includes(raw)
  ) {
    return "restaurant";
  }

  if (
    [
      "store",
      "stores",
      "shop",
      "shops",
      "grocery",
      "supermarket",
      "pharmacy",
      "electronics",
      "home",
      "fashion",
      "cars",
      "car",
      "automotive",
    ].includes(raw)
  ) {
    return "market";
  }

  return null;
}

function buildMerchantInsights(baseRows, selectedType) {
  if (!baseRows.length) return [];

  const avgDeliveryValues = baseRows
    .map((row) => toNumber(row.avg_delivery_minutes))
    .filter((v) => v > 0);
  const avgPriceValues = baseRows
    .map((row) => toNumber(row.avg_effective_price))
    .filter((v) => v > 0);
  const totalOrderValues = baseRows
    .map((row) => toNumber(row.total_orders))
    .filter((v) => v >= 0);
  const ratingValues = baseRows
    .filter((row) => toNumber(row.rating_count) > 0)
    .map((row) => toNumber(row.avg_merchant_rating))
    .filter((v) => v > 0);

  const minDelivery = avgDeliveryValues.length ? Math.min(...avgDeliveryValues) : 0;
  const maxDelivery = avgDeliveryValues.length ? Math.max(...avgDeliveryValues) : 0;
  const minPrice = avgPriceValues.length ? Math.min(...avgPriceValues) : 0;
  const maxPrice = avgPriceValues.length ? Math.max(...avgPriceValues) : 0;
  const minOrders = totalOrderValues.length ? Math.min(...totalOrderValues) : 0;
  const maxOrders = totalOrderValues.length ? Math.max(...totalOrderValues) : 0;
  const p33Price = percentile(avgPriceValues, 0.33);
  const p66Price = percentile(avgPriceValues, 0.66);
  const globalRating = ratingValues.length
    ? ratingValues.reduce((sum, value) => sum + value, 0) / ratingValues.length
    : 4;
  const weights = typeWeights(selectedType);

  return baseRows.map((row) => {
    const merchantId = Number(row.merchant_id);
    const avgDeliveryMinutes = toNumber(row.avg_delivery_minutes);
    const avgEffectivePrice = toNumber(row.avg_effective_price);
    const ratingCount = toNumber(row.rating_count);
    const avgMerchantRating = toNumber(row.avg_merchant_rating);
    const totalOrders = toNumber(row.total_orders);
    const deliveredOrders = toNumber(row.delivered_orders);
    const userOrdersCount = toNumber(row.user_orders_count);
    const onTimeRate = clamp(toNumber(row.on_time_rate), 0, 1);
    const completionRate =
      totalOrders > 0 ? clamp(deliveredOrders / totalOrders, 0, 1) : 0;

    const ratingPrior = 8;
    const weightedRating =
      (avgMerchantRating * ratingCount + globalRating * ratingPrior) /
      (ratingCount + ratingPrior);

    const speedNorm = avgDeliveryMinutes > 0
      ? normalizeInverse(avgDeliveryMinutes, minDelivery, maxDelivery, 0.5)
      : 0.35;
    const speedScore = clamp(speedNorm * 0.72 + onTimeRate * 0.28, 0, 1) * 100;

    const qualityScore =
      clamp((weightedRating / 5) * 0.84 + completionRate * 0.16, 0, 1) * 100;

    const priceNorm = avgEffectivePrice > 0
      ? normalizeInverse(avgEffectivePrice, minPrice, maxPrice, 0.5)
      : 0.5;
    const offerScore = clamp(
      toNumber(row.max_discount_percent) * 0.62 +
        Math.min(toNumber(row.discount_items_count), 8) * 3 +
        (toNumber(row.free_delivery_items_count) > 0 ? 18 : 0),
      0,
      100
    );
    const valueScore =
      clamp(priceNorm * 0.58 + (qualityScore / 100) * 0.42, 0, 1) * 100;
    const popularityScore = normalize(totalOrders, minOrders, maxOrders, 0.25) * 100;

    const compositeScore =
      speedScore * weights.speed +
      qualityScore * weights.quality +
      valueScore * weights.value +
      offerScore * weights.offers +
      popularityScore * weights.popularity;

    return {
      merchantId,
      name: row.name,
      type: row.type,
      activityType: normalizeRegistryActivityType(row.activity_type) || "market",
      discoverySubcategory: normalizeRegistryDiscoverySubcategory(
        row.discovery_subcategory
      ),
      discoverySubcategories: normalizeRegistryDiscoverySubcategoryList(
        row.discovery_subcategories
      ),
      discoverySelectAll: row.discovery_select_all === true,
      description: row.description || null,
      phone: row.phone || null,
      imageUrl: row.image_url || null,
      tagline: row.tagline || null,
      workingHours: row.working_hours || null,
      serviceAreaNote: row.service_area_note || null,
      serviceFlags:
        row.service_flags_json && typeof row.service_flags_json === "object"
          ? row.service_flags_json
          : {},
      badges: Array.isArray(row.badges_json) ? row.badges_json : [],
      supportsChat: row.supports_chat === true,
      supportsAttachments: row.supports_attachments === true,
      supportsPharmacyWorkflow: row.supports_pharmacy_workflow === true,
      isOpen: Boolean(row.is_open),
      hasDiscountOffer: Boolean(row.has_discount_offer),
      hasFreeDeliveryOffer: Boolean(row.has_free_delivery_offer),
      totalOrders,
      deliveredOrders,
      cancelledOrders: toNumber(row.cancelled_orders),
      ratingCount,
      avgMerchantRating: round(avgMerchantRating),
      weightedRating: round(weightedRating),
      avgDeliveryMinutes: round(avgDeliveryMinutes),
      onTimeRate: round(onTimeRate * 100),
      avgEffectivePrice: round(avgEffectivePrice),
      minEffectivePrice: round(toNumber(row.min_effective_price)),
      avgOrderAmount: round(toNumber(row.avg_order_amount)),
      maxDiscountPercent: round(toNumber(row.max_discount_percent)),
      discountItemsCount: toNumber(row.discount_items_count),
      freeDeliveryItemsCount: toNumber(row.free_delivery_items_count),
      completionRate: round(completionRate * 100),
      priceTier: classifyPriceTier(avgEffectivePrice, p33Price, p66Price),
      speedScore: round(speedScore),
      qualityScore: round(qualityScore),
      valueScore: round(valueScore),
      offerScore: round(offerScore),
      popularityScore: round(popularityScore),
      compositeScore: round(compositeScore),
      userOrdersCount,
      lastUserOrderId: row.last_user_order_id ? Number(row.last_user_order_id) : null,
      lastUserOrderedAt: toIsoOrNull(row.last_user_ordered_at),
      lastUserTotalAmount: round(toNumber(row.last_user_total_amount)),
      lastUserItemsCount: toNumber(row.last_user_items_count),
      lastOrderedAt: toIsoOrNull(row.last_ordered_at),
    };
  });
}

function buildRanking(insights) {
  const fastest = sortByScore(insights, (row) => row.speedScore);
  const topRated = sortByScore(insights, (row) => row.qualityScore);
  const bestOffers = sortByScore(insights, (row) => row.offerScore);
  const bestValue = sortByScore(insights, (row) => row.valueScore);
  const mostOrdered = sortByScore(insights, (row) => row.totalOrders);
  const reorder = insights
    .filter((row) => row.userOrdersCount > 0)
    .sort((a, b) => {
      const timeA = a.lastUserOrderedAt ? new Date(a.lastUserOrderedAt).getTime() : 0;
      const timeB = b.lastUserOrderedAt ? new Date(b.lastUserOrderedAt).getTime() : 0;
      if (timeA !== timeB) return timeB - timeA;
      if (b.userOrdersCount !== a.userOrdersCount) {
        return b.userOrdersCount - a.userOrdersCount;
      }
      return (a.name || "").localeCompare(b.name || "");
    })
    .slice(0, 8)
    .map((row) => ({
      merchantId: row.merchantId,
      lastOrderId: row.lastUserOrderId,
      lastOrderedAt: row.lastUserOrderedAt,
      userOrdersCount: row.userOrdersCount,
      lastOrderItemsCount: row.lastUserItemsCount,
      lastOrderTotalAmount: row.lastUserTotalAmount,
    }));

  return {
    fastest: fastest.map((row) => row.merchantId),
    topRated: topRated.map((row) => row.merchantId),
    bestOffers: bestOffers.map((row) => row.merchantId),
    bestValue: bestValue.map((row) => row.merchantId),
    mostOrdered: mostOrdered.map((row) => row.merchantId),
    reorder,
  };
}

function buildCustomerProfile(profileSignals, insights) {
  const summaryAll = profileSignals.summaryAll || {};
  const summaryByType = profileSignals.summaryByType || {};
  const benchmarks = profileSignals.spendingBenchmarks || {};

  const avgAll = toNumber(summaryAll.avg_order_value);
  const avgByType = toNumber(summaryByType.avg_order_value);
  const p35 = toNumber(benchmarks.p35);
  const p70 = toNumber(benchmarks.p70);

  const weightedUserPrice = (() => {
    const rows = insights.filter(
      (row) => row.userOrdersCount > 0 && row.avgEffectivePrice > 0
    );
    if (!rows.length) return 0;
    const totalWeight = rows.reduce((sum, row) => sum + row.userOrdersCount, 0);
    if (totalWeight <= 0) return 0;
    const weighted = rows.reduce(
      (sum, row) => sum + row.avgEffectivePrice * row.userOrdersCount,
      0
    );
    return weighted / totalWeight;
  })();

  const catalogMedianPrice = (() => {
    const values = insights
      .map((row) => row.avgEffectivePrice)
      .filter((value) => value > 0);
    return percentile(values, 0.5);
  })();

  let priceSensitivity = "balanced";
  if (weightedUserPrice > 0 && catalogMedianPrice > 0) {
    if (weightedUserPrice <= catalogMedianPrice * 0.92) priceSensitivity = "high";
    else if (weightedUserPrice >= catalogMedianPrice * 1.12) {
      priceSensitivity = "low";
    }
  }

  return {
    ordersCount120d: toNumber(summaryAll.orders_count),
    deliveredCount120d: toNumber(summaryAll.delivered_count),
    avgOrderValue120d: round(avgAll),
    totalSpend120d: round(toNumber(summaryAll.total_spend)),
    ordersCountInCategory120d: toNumber(summaryByType.orders_count),
    avgOrderValueInCategory120d: round(avgByType),
    spendingBand: spendingBand(avgAll, p35, p70),
    priceSensitivity,
    preferredMerchantTypeMix: (profileSignals.typeMix || []).map((row) => ({
      type: row.type,
      ordersCount: toNumber(row.orders_count),
    })),
    topMerchants: (profileSignals.topMerchants || []).map((row) => ({
      merchantId: Number(row.merchant_id),
      merchantName: row.merchant_name,
      ordersCount: toNumber(row.orders_count),
      lastOrderedAt: toIsoOrNull(row.last_ordered_at),
    })),
    peakOrderHours: (profileSignals.topOrderHours || []).map((row) => ({
      hour: toNumber(row.hour),
      ordersCount: toNumber(row.orders_count),
    })),
  };
}

export async function getCustomerDiscovery(customerUserId, type, options = {}) {
  const normalizedType = normalizeType(type);
  const activityType = normalizeRegistryActivityType(options.activityType);
  const discoverySubcategory = normalizeRegistryDiscoverySubcategory(
    options.discoverySubcategory
  );
  const [baseRows, profileSignals] = await Promise.all([
    repo.getMerchantsDiscoveryBase({
      type: normalizedType,
      customerUserId,
      activityType,
      discoverySubcategory,
    }),
    repo.getCustomerProfileSignals({
      type: normalizedType,
      customerUserId,
    }),
  ]);

  const insights = buildMerchantInsights(baseRows, normalizedType || "restaurant");
  const ranking = buildRanking(insights);
  const profile = buildCustomerProfile(profileSignals, insights);

  return {
    generatedAt: new Date().toISOString(),
    type: normalizedType,
    activityType,
    discoverySubcategory,
    ranking,
    profile,
    algorithm: {
      version: "merchant-intelligence-v1",
      weights: typeWeights(normalizedType || "restaurant"),
      nearestDistanceUsed: false,
    },
    merchants: insights,
  };
}
