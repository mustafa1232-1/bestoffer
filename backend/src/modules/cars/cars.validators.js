function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
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
