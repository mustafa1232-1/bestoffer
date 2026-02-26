import { hashPin } from "../../shared/utils/hash.js";
import * as repo from "./merchants.repo.js";

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

  const merchant = {
    name: dto.name.trim(),
    type: dto.type,
    description: normalizeOptional(dto.description),
    phone: normalizeOptional(dto.phone),
    imageUrl: normalizeOptional(dto.imageUrl),
  };

  let ownerToCreate = null;
  let ownerPinHash = null;

  if (!hasOwnerUserId && hasOwnerObject) {
    ownerToCreate = {
      fullName: dto.owner.fullName.trim(),
      phone: dto.owner.phone.trim(),
      block: dto.owner.block.trim(),
      buildingNumber: dto.owner.buildingNumber.trim(),
      apartment: dto.owner.apartment.trim(),
      imageUrl: normalizeOptional(dto.owner.imageUrl),
    };
    ownerPinHash = await hashPin(dto.owner.pin);
  }

  try {
    return await repo.createMerchantWithOwnerLink({
      merchant,
      approvedByUserId,
      ownerUserId,
      ownerToCreate,
      ownerPinHash,
    });
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

export async function listMerchants(type) {
  return repo.getAllMerchants(type);
}

export async function listMerchantProducts(merchantId) {
  return repo.getPublicMerchantProducts(merchantId);
}

export async function listMerchantCategories(merchantId) {
  return repo.getPublicMerchantCategories(merchantId);
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
      description: row.description || null,
      phone: row.phone || null,
      imageUrl: row.image_url || null,
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

export async function getCustomerDiscovery(customerUserId, type) {
  const normalizedType = normalizeType(type);
  const [baseRows, profileSignals] = await Promise.all([
    repo.getMerchantsDiscoveryBase({
      type: normalizedType,
      customerUserId,
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
