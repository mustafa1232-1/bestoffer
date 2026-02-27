import {
  brandTierMap,
  brandTierRanges,
  carCatalog,
  getCatalogBrand,
  modelProfiles,
  normalizeKey,
  profileKey,
} from "./cars.catalog.js";

const profileMap = new Map(
  modelProfiles.map((item) => [profileKey(item.brand, item.model), item])
);

const BODY_TYPES = ["sedan", "suv", "crossover", "hatchback", "pickup", "van"];

function bodyTypeLabel(value) {
  const labels = {
    any: "Any",
    sedan: "Sedan",
    suv: "SUV",
    crossover: "Crossover",
    hatchback: "Hatchback",
    pickup: "Pickup",
    van: "Van",
  };
  return labels[value] || "Any";
}

function usageLabel(value) {
  const labels = {
    taxi: "Taxi",
    personal: "Personal",
    work: "Work",
    mixed: "Mixed",
  };
  return labels[value] || "Personal";
}

function priorityLabel(value) {
  const labels = {
    balanced: "Balanced",
    lowest_price: "Lowest Price",
    lowest_fuel_cost: "Lowest Fuel Cost",
    comfort: "Comfort",
    space: "Space",
    resale: "Resale",
    maintenance: "Maintenance",
  };
  return labels[value] || "Balanced";
}

function inferBodyType(modelName) {
  const name = normalizeKey(modelName);
  if (name.includes("pickup") || name.includes("d-max") || name.includes("poer")) {
    return "pickup";
  }
  if (name.includes("van") || name.includes("staria")) return "van";
  if (
    name.includes("suv") ||
    name.includes("x5") ||
    name.includes("x6") ||
    name.includes("q7") ||
    name.includes("prado") ||
    name.includes("patrol") ||
    name.includes("tahoe")
  ) {
    return "suv";
  }
  if (
    name.includes("cross") ||
    name.includes("cx-") ||
    name.includes("sportage") ||
    name.includes("tucson")
  ) {
    return "crossover";
  }
  if (name.includes("swift") || name.includes("yaris") || name.includes("golf")) {
    return "hatchback";
  }
  return "sedan";
}

function inferBrandRange(brand) {
  const tier = brandTierMap[brand] || "mid";
  return brandTierRanges[tier] || brandTierRanges.mid;
}

function normalizePriceRange(range) {
  if (!Array.isArray(range) || range.length !== 2) return null;
  const min = Number(range[0]);
  const max = Number(range[1]);
  if (!Number.isFinite(min) || !Number.isFinite(max)) return null;
  return { min, max };
}

function mergedAnyRange(newPrice, usedPrice) {
  if (!newPrice && !usedPrice) return null;
  if (!newPrice) return usedPrice;
  if (!usedPrice) return newPrice;
  return {
    min: Math.min(newPrice.min, usedPrice.min),
    max: Math.max(newPrice.max, usedPrice.max),
  };
}

function resolvePriceRange(profile, condition, brand) {
  const inferred = inferBrandRange(brand);
  const newPrice = normalizePriceRange(profile?.newPriceM) ||
    normalizePriceRange(inferred?.newPriceM);
  const usedPrice = normalizePriceRange(profile?.usedPriceM) ||
    normalizePriceRange(inferred?.usedPriceM);

  if (condition === "new") return newPrice;
  if (condition === "used") return usedPrice;
  return mergedAnyRange(newPrice, usedPrice);
}

function overlapsRange(a, b) {
  return a.max >= b.min && a.min <= b.max;
}

function budgetScore(price, budget) {
  if (!overlapsRange(price, budget)) return 0;
  const overlapMin = Math.max(price.min, budget.min);
  const overlapMax = Math.min(price.max, budget.max);
  const overlapWidth = overlapMax - overlapMin + 1;
  const budgetWidth = budget.max - budget.min + 1;
  if (budgetWidth <= 0) return 0;
  const ratio = overlapWidth / budgetWidth;
  return Math.max(5, Math.min(30, Math.round(ratio * 30)));
}

function priorityScore(profile, priority) {
  switch (priority) {
    case "lowest_price":
      return profile.maintenance;
    case "lowest_fuel_cost":
      return profile.fuelEfficiency;
    case "comfort":
      return profile.comfort;
    case "space":
      return profile.space;
    case "resale":
      return profile.resale;
    case "maintenance":
      return profile.maintenance;
    default:
      return Math.round(
        (profile.reliability +
          profile.fuelEfficiency +
          profile.comfort +
          profile.resale +
          profile.maintenance) /
          5
      );
  }
}

function usageScore(profile, usage) {
  if (usage === "taxi") return profile.taxiFit;
  if (usage === "work") return profile.workFit;
  if (usage === "mixed") {
    return Math.round((profile.taxiFit + profile.workFit + profile.personalFit) / 3);
  }
  return profile.personalFit;
}

function toBrowseItem(brand, model, { condition = "any" } = {}) {
  const key = profileKey(brand, model);
  const profile = profileMap.get(key) || null;
  const bodyType = profile?.bodyType || inferBodyType(model);
  const priceRange = resolvePriceRange(profile, condition, brand);

  const currentYear = new Date().getFullYear();
  const yearRange =
    condition === "new"
      ? { min: currentYear - 2, max: currentYear }
      : condition === "used"
      ? { min: currentYear - 18, max: currentYear }
      : { min: currentYear - 18, max: currentYear };

  const seats = profile?.seats || (bodyType === "suv" || bodyType === "pickup" ? 7 : 5);
  const fuelType = profile?.isElectric
    ? "electric"
    : profile?.hasHybrid
    ? "hybrid"
    : "fuel";

  return {
    id: `${brand}-${model}`.replaceAll(" ", "_").toLowerCase(),
    brand,
    model,
    bodyType,
    seats,
    fuelType,
    transmission: profile?.hasAutomatic
      ? profile?.hasManual
        ? "automatic_or_manual"
        : "automatic"
      : "manual",
    conditionAvailability: {
      new: !!(profile?.newPriceM || inferBrandRange(brand)?.newPriceM),
      used: !!(profile?.usedPriceM || inferBrandRange(brand)?.usedPriceM),
    },
    estimatedPriceM: priceRange,
    estimatedYearRange: yearRange,
    metadata: profile
      ? {
          reliability: profile.reliability,
          maintenance: profile.maintenance,
          resale: profile.resale,
          comfort: profile.comfort,
          space: profile.space,
          fuelEfficiency: profile.fuelEfficiency,
        }
      : null,
  };
}

function filterByQuery(items, query) {
  let data = items;

  if (query.brand) {
    const key = normalizeKey(query.brand);
    data = data.filter((item) => normalizeKey(item.brand) === key);
  }

  if (query.model) {
    const key = normalizeKey(query.model);
    data = data.filter((item) => normalizeKey(item.model).includes(key));
  }

  if (query.search) {
    const search = normalizeKey(query.search);
    data = data.filter((item) =>
      normalizeKey(`${item.brand} ${item.model}`).includes(search)
    );
  }

  if (query.bodyType !== "any") {
    data = data.filter((item) => item.bodyType === query.bodyType);
  }

  if (query.condition !== "any") {
    data = data.filter(
      (item) => item.conditionAvailability && item.conditionAvailability[query.condition]
    );
  }

  if (query.yearFrom !== null || query.yearTo !== null) {
    const from = query.yearFrom ?? 1985;
    const to = query.yearTo ?? 2035;
    data = data.filter(
      (item) =>
        item.estimatedYearRange &&
        overlapsRange(
          { min: item.estimatedYearRange.min, max: item.estimatedYearRange.max },
          { min: from, max: to }
        )
    );
  }

  return data;
}

function sortByPriceAndName(items) {
  return [...items].sort((a, b) => {
    const aMin = a.estimatedPriceM?.min ?? 9999;
    const bMin = b.estimatedPriceM?.min ?? 9999;
    if (aMin !== bMin) return aMin - bMin;
    const brandCmp = a.brand.localeCompare(b.brand);
    if (brandCmp !== 0) return brandCmp;
    return a.model.localeCompare(b.model);
  });
}

export function listBrands({ search = "" } = {}) {
  const searchKey = normalizeKey(search);
  const rows = carCatalog
    .filter((item) => !searchKey || normalizeKey(item.brand).includes(searchKey))
    .map((item) => ({
      name: item.brand,
      modelsCount: item.models.length,
      tier: brandTierMap[item.brand] || "mid",
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  return {
    brands: rows,
    total: rows.length,
  };
}

export function listModels(brand, { search = "" } = {}) {
  const row = getCatalogBrand(brand);
  if (!row) {
    return {
      brand,
      models: [],
      total: 0,
    };
  }

  const searchKey = normalizeKey(search);
  const models = row.models
    .filter((model) => !searchKey || normalizeKey(model).includes(searchKey))
    .map((model) => {
      const item = toBrowseItem(row.brand, model, { condition: "any" });
      return {
        name: model,
        bodyType: item.bodyType,
        estimatedPriceM: item.estimatedPriceM,
      };
    });

  return {
    brand: row.brand,
    models,
    total: models.length,
  };
}

export function browseCars(query) {
  const allItems = carCatalog.flatMap((brandRow) =>
    brandRow.models.map((model) =>
      toBrowseItem(brandRow.brand, model, {
        condition: query.condition || "any",
      })
    )
  );

  const filtered = sortByPriceAndName(filterByQuery(allItems, query));
  const total = filtered.length;
  const start = query.offset || 0;
  const end = start + (query.limit || 60);

  return {
    items: filtered.slice(start, end),
    total,
    limit: query.limit,
    offset: query.offset,
    hasMore: end < total,
  };
}

function matchText(profile, freeText) {
  const q = normalizeKey(freeText);
  if (!q) return true;
  const source = normalizeKey(`${profile.brand} ${profile.model}`);
  return source.includes(q);
}

function buildReasons({ profile, condition, usage, priority, price }) {
  const reasons = [
    `Price range matches your budget: ${price.min}-${price.max}M IQD`,
    `Good fit for usage: ${usageLabel(usage)}`,
  ];

  if (priority === "lowest_fuel_cost") {
    reasons.push("Strong fuel efficiency compared with nearby alternatives");
  } else if (priority === "resale") {
    reasons.push("Better resale potential in the local market");
  } else if (priority === "maintenance" || priority === "lowest_price") {
    reasons.push("Maintenance and spare-parts profile is practical");
  } else if (priority === "comfort") {
    reasons.push("Comfort score is above average for daily driving");
  } else if (priority === "space") {
    reasons.push("Cabin and cargo space are suitable for your needs");
  } else {
    reasons.push("Balanced performance across reliability, comfort and cost");
  }

  if (condition === "new") reasons.push("Focused on new-car offers");
  if (condition === "used") reasons.push("Focused on used-car offers");

  return reasons;
}

function scoreCandidates(criteria) {
  const budget = { min: criteria.budgetMinM, max: criteria.budgetMaxM };
  const items = [];

  for (const profile of modelProfiles) {
    if (criteria.bodyType !== "any" && profile.bodyType !== criteria.bodyType) continue;
    if (profile.seats < criteria.minSeats) continue;
    if (!matchText(profile, criteria.freeText)) continue;

    const price = resolvePriceRange(profile, criteria.condition, profile.brand);
    if (!price) continue;
    if (!overlapsRange(price, budget)) continue;

    if (criteria.transmission === "automatic" && !profile.hasAutomatic) continue;
    if (criteria.transmission === "manual" && !profile.hasManual) continue;

    if (criteria.fuelPreference === "hybrid" && !profile.hasHybrid) continue;
    if (criteria.fuelPreference === "electric" && !profile.isElectric) continue;
    if (criteria.fuelPreference === "economy" && profile.fuelEfficiency < 7) continue;

    let score = 0;
    score += budgetScore(price, budget);
    score += usageScore(profile, criteria.usage) * 2;
    score += priorityScore(profile, criteria.priority);
    score += Math.round(profile.reliability / 2);

    if (criteria.fuelPreference === "hybrid" && profile.hasHybrid) score += 8;
    if (criteria.fuelPreference === "electric" && profile.isElectric) score += 10;
    if (criteria.fuelPreference === "economy" && profile.fuelEfficiency >= 8) score += 6;

    items.push({
      id: `${profile.brand}-${profile.model}`.replaceAll(" ", "_").toLowerCase(),
      brand: profile.brand,
      model: profile.model,
      bodyType: profile.bodyType,
      seats: profile.seats,
      score,
      estimatedPriceM: price,
      reasons: buildReasons({
        profile,
        condition: criteria.condition,
        usage: criteria.usage,
        priority: criteria.priority,
        price,
      }),
      tags: {
        usage: usageLabel(criteria.usage),
        priority: priorityLabel(criteria.priority),
        bodyType: bodyTypeLabel(profile.bodyType),
      },
      searchQuery: `سيارات ${profile.brand} ${profile.model}`,
    });
  }

  items.sort((a, b) => b.score - a.score);
  return items;
}

function relaxedCriteria(criteria) {
  return {
    ...criteria,
    budgetMinM: Math.max(5, criteria.budgetMinM - 8),
    budgetMaxM: Math.min(300, criteria.budgetMaxM + 8),
    bodyType: "any",
    condition: "any",
    fuelPreference: "any",
    transmission: "any",
    freeText: "",
    minSeats: Math.min(criteria.minSeats, 5),
  };
}

export function smartSearch(criteria) {
  let items = scoreCandidates(criteria);
  let usedRelaxedCriteria = false;

  if (items.length === 0) {
    usedRelaxedCriteria = true;
    items = scoreCandidates(relaxedCriteria(criteria));
  }

  const limit = criteria.limit || 6;

  return {
    criteria: {
      budgetMinM: criteria.budgetMinM,
      budgetMaxM: criteria.budgetMaxM,
      usage: criteria.usage,
      condition: criteria.condition,
      bodyType: criteria.bodyType,
      fuelPreference: criteria.fuelPreference,
      transmission: criteria.transmission,
      priority: criteria.priority,
      minSeats: criteria.minSeats,
    },
    usedRelaxedCriteria,
    recommendations: items.slice(0, limit),
    totalCandidates: items.length,
  };
}
