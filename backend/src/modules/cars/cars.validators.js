function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function toNonNegativeInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 ? n : null;
}

function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toTrimmedString(value, max = 2000) {
  if (value === undefined || value === null) return null;
  const text = String(value).trim();
  if (!text) return null;
  return text.length > max ? text.slice(0, max) : text;
}

function inEnum(value, allowed) {
  return allowed.includes(value);
}

export function validateBrowseCars(query) {
  const errors = [];
  const out = {};

  if (query.brand !== undefined) out.brand = String(query.brand).trim();
  if (query.model !== undefined) out.model = String(query.model).trim();
  if (query.search !== undefined) out.search = String(query.search).trim();

  const condition = String(query.condition || "any").trim().toLowerCase();
  if (!inEnum(condition, ["any", "new", "used"])) errors.push("condition");
  out.condition = condition;

  const bodyType = String(query.bodyType || "any").trim().toLowerCase();
  if (
    !inEnum(bodyType, ["any", "sedan", "suv", "crossover", "hatchback", "pickup", "van"])
  ) {
    errors.push("bodyType");
  }
  out.bodyType = bodyType;

  const yearFrom = query.yearFrom === undefined ? null : toInt(query.yearFrom);
  const yearTo = query.yearTo === undefined ? null : toInt(query.yearTo);
  if (yearFrom !== null && (yearFrom < 1985 || yearFrom > 2035)) errors.push("yearFrom");
  if (yearTo !== null && (yearTo < 1985 || yearTo > 2035)) errors.push("yearTo");
  if (yearFrom !== null && yearTo !== null && yearFrom > yearTo) errors.push("yearRange");
  out.yearFrom = yearFrom;
  out.yearTo = yearTo;

  const limit = toInt(query.limit ?? 60);
  const offset = toInt(query.offset ?? 0);
  if (limit === null || limit < 1 || limit > 250) errors.push("limit");
  if (offset === null || offset < 0) errors.push("offset");
  out.limit = limit ?? 60;
  out.offset = offset ?? 0;

  return { ok: errors.length === 0, errors, value: out };
}

export function validateSmartSearch(body) {
  const errors = [];
  const out = {};

  const budgetMinM = toNumber(body?.budgetMinM);
  const budgetMaxM = toNumber(body?.budgetMaxM);
  if (budgetMinM === null || budgetMinM < 1 || budgetMinM > 400) errors.push("budgetMinM");
  if (budgetMaxM === null || budgetMaxM < 1 || budgetMaxM > 400) errors.push("budgetMaxM");
  if (budgetMinM !== null && budgetMaxM !== null && budgetMinM > budgetMaxM) {
    errors.push("budgetRange");
  }
  out.budgetMinM = budgetMinM;
  out.budgetMaxM = budgetMaxM;

  out.bodyType = String(body?.bodyType || "any").trim().toLowerCase();
  if (
    !inEnum(out.bodyType, ["any", "sedan", "suv", "crossover", "hatchback", "pickup", "van"])
  ) {
    errors.push("bodyType");
  }

  out.usage = String(body?.usage || "personal").trim().toLowerCase();
  if (!inEnum(out.usage, ["taxi", "personal", "work", "mixed"])) errors.push("usage");

  out.condition = String(body?.condition || "any").trim().toLowerCase();
  if (!inEnum(out.condition, ["any", "new", "used"])) errors.push("condition");

  out.fuelPreference = String(body?.fuelPreference || "any")
    .trim()
    .toLowerCase();
  if (!inEnum(out.fuelPreference, ["any", "economy", "hybrid", "electric"])) {
    errors.push("fuelPreference");
  }

  out.transmission = String(body?.transmission || "any")
    .trim()
    .toLowerCase();
  if (!inEnum(out.transmission, ["any", "automatic", "manual"])) {
    errors.push("transmission");
  }

  out.priority = String(body?.priority || "balanced")
    .trim()
    .toLowerCase();
  if (
    !inEnum(out.priority, [
      "balanced",
      "lowest_price",
      "lowest_fuel_cost",
      "comfort",
      "space",
      "resale",
      "maintenance",
    ])
  ) {
    errors.push("priority");
  }

  const minSeats = toInt(body?.minSeats ?? 4);
  if (minSeats === null || minSeats < 2 || minSeats > 10) errors.push("minSeats");
  out.minSeats = minSeats ?? 4;

  out.freeText = String(body?.freeText || "").trim();
  if (out.freeText.length > 120) errors.push("freeText");

  const limit = toInt(body?.limit ?? 6);
  if (limit === null || limit < 1 || limit > 30) errors.push("limit");
  out.limit = limit ?? 6;

  return { ok: errors.length === 0, errors, value: out };
}

export function validateCarListingQuery(query = {}) {
  const errors = [];
  const out = {};

  out.brand = toTrimmedString(query.brand, 120);
  out.model = toTrimmedString(query.model, 120);
  out.search = toTrimmedString(query.search, 120);
  out.city = toTrimmedString(query.city, 120);

  const condition =
    query.condition == null || query.condition === ""
      ? null
      : String(query.condition).trim().toLowerCase();
  if (condition != null && !inEnum(condition, ["new", "used"])) errors.push("condition");
  out.condition = condition;

  const bodyType =
    query.bodyType == null || query.bodyType === ""
      ? null
      : String(query.bodyType).trim().toLowerCase();
  if (
    bodyType != null &&
    !inEnum(bodyType, ["sedan", "suv", "crossover", "hatchback", "pickup", "van"])
  ) {
    errors.push("bodyType");
  }
  out.bodyType = bodyType;

  const minPrice = query.minPrice == null || query.minPrice === "" ? null : toNumber(query.minPrice);
  const maxPrice = query.maxPrice == null || query.maxPrice === "" ? null : toNumber(query.maxPrice);
  if (minPrice != null && minPrice < 0) errors.push("minPrice");
  if (maxPrice != null && maxPrice < 0) errors.push("maxPrice");
  if (minPrice != null && maxPrice != null && minPrice > maxPrice) errors.push("priceRange");
  out.minPrice = minPrice;
  out.maxPrice = maxPrice;

  const sort = String(query.sort || "recent").trim().toLowerCase();
  if (!inEnum(sort, ["recent", "oldest", "price_low", "price_high"])) errors.push("sort");
  out.sort = sort;

  const limit = toInt(query.limit ?? 20);
  const offset = toNonNegativeInt(query.offset ?? 0);
  if (limit === null || limit < 1 || limit > 100) errors.push("limit");
  if (offset === null) errors.push("offset");
  out.limit = limit ?? 20;
  out.offset = offset ?? 0;

  return { ok: errors.length === 0, errors, value: out };
}

export function validateCarListingBody(body = {}) {
  const errors = [];
  const out = {};

  out.title = toTrimmedString(body.title, 180);
  out.description = toTrimmedString(body.description, 4000);
  out.brand = toTrimmedString(body.brand, 120);
  out.model = toTrimmedString(body.model, 120);
  out.city = toTrimmedString(body.city, 120);
  out.phone = toTrimmedString(body.phone, 32);
  out.color = toTrimmedString(body.color, 60);

  const modelYear = toInt(body.modelYear);
  if (modelYear === null || modelYear < 1980 || modelYear > 2035) errors.push("modelYear");
  out.modelYear = modelYear ?? 2024;

  const condition = String(body.condition || "used").trim().toLowerCase();
  if (!inEnum(condition, ["new", "used"])) errors.push("condition");
  out.condition = condition;

  const price = toNumber(body.price);
  if (price === null || price < 0) errors.push("price");
  out.price = price ?? 0;

  const mileageKm =
    body.mileageKm == null || body.mileageKm === "" ? null : toNonNegativeInt(body.mileageKm);
  if (condition === "used" && mileageKm == null) errors.push("mileageKm");
  out.mileageKm = mileageKm;

  const transmission = String(body.transmission || "automatic").trim().toLowerCase();
  if (!inEnum(transmission, ["automatic", "manual"])) errors.push("transmission");
  out.transmission = transmission;

  const fuelType = String(body.fuelType || "fuel").trim().toLowerCase();
  if (!inEnum(fuelType, ["fuel", "hybrid", "electric"])) errors.push("fuelType");
  out.fuelType = fuelType;

  const bodyType = String(body.bodyType || "sedan").trim().toLowerCase();
  if (!inEnum(bodyType, ["sedan", "suv", "crossover", "hatchback", "pickup", "van"])) {
    errors.push("bodyType");
  }
  out.bodyType = bodyType;

  if (!out.title) errors.push("title");
  if (!out.brand) errors.push("brand");
  if (!out.model) errors.push("model");
  if (!out.phone) errors.push("phone");

  return { ok: errors.length === 0, errors, value: out };
}

export function validateUpdateCarListingBody(body = {}) {
  const errors = [];
  const out = {};
  const allowedKeys = [
    "title",
    "description",
    "brand",
    "model",
    "modelYear",
    "condition",
    "price",
    "mileageKm",
    "city",
    "phone",
    "transmission",
    "fuelType",
    "bodyType",
    "color",
  ];
  const hasAny = allowedKeys.some((key) => Object.prototype.hasOwnProperty.call(body, key));
  if (!hasAny) errors.push("empty_update");

  if (body.title !== undefined) {
    out.title = toTrimmedString(body.title, 180);
    if (out.title == null) errors.push("title");
  }
  if (body.description !== undefined) out.description = toTrimmedString(body.description, 4000);
  if (body.brand !== undefined) {
    out.brand = toTrimmedString(body.brand, 120);
    if (out.brand == null) errors.push("brand");
  }
  if (body.model !== undefined) {
    out.model = toTrimmedString(body.model, 120);
    if (out.model == null) errors.push("model");
  }
  if (body.modelYear !== undefined) {
    out.modelYear = toInt(body.modelYear);
    if (out.modelYear === null || out.modelYear < 1980 || out.modelYear > 2035) {
      errors.push("modelYear");
    }
  }
  if (body.condition !== undefined) {
    out.condition = String(body.condition || "").trim().toLowerCase();
    if (!inEnum(out.condition, ["new", "used"])) errors.push("condition");
  }
  if (body.price !== undefined) {
    out.price = toNumber(body.price);
    if (out.price === null || out.price < 0) errors.push("price");
  }
  if (body.mileageKm !== undefined) {
    out.mileageKm = body.mileageKm === "" ? null : toNonNegativeInt(body.mileageKm);
    if (body.mileageKm !== "" && out.mileageKm === null) errors.push("mileageKm");
  }
  if (body.city !== undefined) out.city = toTrimmedString(body.city, 120);
  if (body.phone !== undefined) {
    out.phone = toTrimmedString(body.phone, 32);
    if (out.phone == null) errors.push("phone");
  }
  if (body.transmission !== undefined) {
    out.transmission = String(body.transmission || "").trim().toLowerCase();
    if (!inEnum(out.transmission, ["automatic", "manual"])) errors.push("transmission");
  }
  if (body.fuelType !== undefined) {
    out.fuelType = String(body.fuelType || "").trim().toLowerCase();
    if (!inEnum(out.fuelType, ["fuel", "hybrid", "electric"])) errors.push("fuelType");
  }
  if (body.bodyType !== undefined) {
    out.bodyType = String(body.bodyType || "").trim().toLowerCase();
    if (!inEnum(out.bodyType, ["sedan", "suv", "crossover", "hatchback", "pickup", "van"])) {
      errors.push("bodyType");
    }
  }
  if (body.color !== undefined) out.color = toTrimmedString(body.color, 60);

  return { ok: errors.length === 0, errors, value: out };
}

export function validateMarkCarListingStatusBody(body = {}) {
  const errors = [];
  const nextStatus = String(body.nextStatus || "").trim().toLowerCase();
  if (!inEnum(nextStatus, ["active", "sold", "archived"])) errors.push("nextStatus");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      nextStatus,
    },
  };
}
