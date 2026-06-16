function toTrimmedString(value, max = 2000) {
  if (value === undefined || value === null) return null;
  const text = String(value).trim();
  if (!text) return null;
  return text.length > max ? text.slice(0, max) : text;
}

function toPositiveInt(value, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return null;
  if (parsed < min || parsed > max) return null;
  return parsed;
}

function toNullableInt(value, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return null;
  if (parsed < min || parsed > max) return null;
  return parsed;
}

function toNumber(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

function parseBool(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
    if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  }
  return fallback;
}

function parseOptionalBool(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
    if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  }
  return null;
}

function normalizePurpose(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["sale", "rent"].includes(normalized)) return normalized;
  return null;
}

function normalizeStatus(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (
    [
      "pending_admin_review",
      "active",
      "sold",
      "rented",
      "archived",
      "hidden_due_subscription_expiry",
    ].includes(normalized)
  ) {
    return normalized;
  }
  return null;
}

function normalizeBankSettlementMode(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["none", "partial", "full"].includes(normalized)) return normalized;
  return null;
}

function normalizePaymentMethod(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["cash", "installments", "negotiable"].includes(normalized)) {
    return normalized;
  }
  return null;
}

function normalizeSort(value) {
  const normalized = String(value || "recent").trim().toLowerCase();
  if (
    [
      "recent",
      "oldest",
      "price_low",
      "price_high",
      "most_viewed",
    ].includes(normalized)
  ) {
    return normalized;
  }
  return null;
}

export function validateListListingsQuery(query = {}) {
  const errors = [];
  const purpose =
    query.purpose == null || query.purpose === ""
      ? null
      : normalizePurpose(query.purpose);
  const search = toTrimmedString(query.search, 120);
  const city = toTrimmedString(query.city, 120);
  const block = toTrimmedString(query.block, 24);
  const areaSqm = toNullableInt(query.areaSqm);
  const areaMin = toNullableInt(query.areaMin);
  const areaMax = toNullableInt(query.areaMax);
  const furnished = parseOptionalBool(query.furnished);
  const availableOnly = parseOptionalBool(query.availableOnly);
  const featuredOnly = parseOptionalBool(query.featuredOnly);
  const bankSettlementMode =
    query.bankSettlementMode == null || query.bankSettlementMode === ""
      ? null
      : normalizeBankSettlementMode(query.bankSettlementMode);
  const paymentMethod =
    query.paymentMethod == null || query.paymentMethod === ""
      ? null
      : normalizePaymentMethod(query.paymentMethod);
  const minPrice =
    query.minPrice == null || query.minPrice === "" ? null : toNumber(query.minPrice);
  const maxPrice =
    query.maxPrice == null || query.maxPrice === "" ? null : toNumber(query.maxPrice);
  const roomsCount = toNullableInt(query.roomsCount);
  const bathroomsCount = toNullableInt(query.bathroomsCount);
  const floorMin = toNullableInt(query.floorMin);
  const floorMax = toNullableInt(query.floorMax);
  const sort = normalizeSort(query.sort || "recent");
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 24;
  const offset = toPositiveInt(query.offset, { min: 0, max: 100000 }) || 0;

  if (query.purpose !== undefined && query.purpose !== "" && !purpose) {
    errors.push("purpose");
  }
  if (query.areaSqm !== undefined && areaSqm == null) errors.push("areaSqm");
  if (query.areaMin !== undefined && areaMin == null) errors.push("areaMin");
  if (query.areaMax !== undefined && areaMax == null) errors.push("areaMax");
  if (query.furnished !== undefined && query.furnished !== "" && furnished == null) {
    errors.push("furnished");
  }
  if (
    query.availableOnly !== undefined &&
    query.availableOnly !== "" &&
    availableOnly == null
  ) {
    errors.push("availableOnly");
  }
  if (
    query.featuredOnly !== undefined &&
    query.featuredOnly !== "" &&
    featuredOnly == null
  ) {
    errors.push("featuredOnly");
  }
  if (
    query.bankSettlementMode !== undefined &&
    query.bankSettlementMode !== "" &&
    !bankSettlementMode
  ) {
    errors.push("bankSettlementMode");
  }
  if (
    query.paymentMethod !== undefined &&
    query.paymentMethod !== "" &&
    !paymentMethod
  ) {
    errors.push("paymentMethod");
  }
  if (
    minPrice != null &&
    maxPrice != null &&
    Number.isFinite(minPrice) &&
    Number.isFinite(maxPrice) &&
    maxPrice < minPrice
  ) {
    errors.push("priceRange");
  }
  if (areaMin != null && areaMax != null && areaMax < areaMin) {
    errors.push("areaRange");
  }
  if (floorMin != null && floorMax != null && floorMax < floorMin) {
    errors.push("floorRange");
  }
  if (!sort) errors.push("sort");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      purpose,
      search,
      city,
      block,
      areaSqm,
      areaMin,
      areaMax,
      furnished,
      availableOnly: availableOnly === true,
      featuredOnly: featuredOnly === true,
      bankSettlementMode,
      paymentMethod,
      minPrice,
      maxPrice,
      roomsCount,
      bathroomsCount,
      floorMin,
      floorMax,
      sort: sort || "recent",
      limit,
      offset,
    },
  };
}

function parseListingPayload(body = {}, { partial = false } = {}) {
  const errors = [];
  const purpose = body.purpose === undefined && partial
    ? undefined
    : normalizePurpose(body.purpose);
  const title = body.title === undefined && partial
    ? undefined
    : toTrimmedString(body.title, 180);
  const description = body.description === undefined
    ? undefined
    : toTrimmedString(body.description, 4000);
  const areaSqm = body.areaSqm === undefined && partial
    ? undefined
    : toPositiveInt(body.areaSqm);
  const bankSettlementAmount = body.bankSettlementAmount === undefined
    ? undefined
    : toNumber(body.bankSettlementAmount);
  const bankSettlementMode = body.bankSettlementMode === undefined
    ? undefined
    : normalizeBankSettlementMode(body.bankSettlementMode);
  const paymentMethod = body.paymentMethod === undefined
    ? undefined
    : normalizePaymentMethod(body.paymentMethod);
  const furnished = body.furnished === undefined
    ? undefined
    : parseBool(body.furnished, false);
  const furnishingDescription = body.furnishingDescription === undefined
    ? undefined
    : toTrimmedString(body.furnishingDescription, 2000);
  const phone = body.phone === undefined && partial
    ? undefined
    : toTrimmedString(body.phone, 32);
  const price = body.price === undefined && partial
    ? undefined
    : toNumber(body.price);
  const city = body.city === undefined ? undefined : toTrimmedString(body.city, 120);
  const block = body.block === undefined ? undefined : toTrimmedString(body.block, 24);
  const buildingNumber =
    body.buildingNumber === undefined
      ? undefined
      : toTrimmedString(body.buildingNumber, 24);
  const apartmentNumber =
    body.apartmentNumber === undefined
      ? undefined
      : toTrimmedString(body.apartmentNumber, 24);
  const roomsCount =
    body.roomsCount === undefined ? undefined : toNullableInt(body.roomsCount);
  const bathroomsCount =
    body.bathroomsCount === undefined
      ? undefined
      : toNullableInt(body.bathroomsCount);
  const floorNumber =
    body.floorNumber === undefined ? undefined : toNullableInt(body.floorNumber);
  const detailsJson =
    body.detailsJson === undefined
      ? undefined
      : body.detailsJson &&
          typeof body.detailsJson === "object" &&
          !Array.isArray(body.detailsJson)
        ? body.detailsJson
        : null;

  if (!partial || body.purpose !== undefined) {
    if (!purpose) errors.push("purpose");
  }
  if (!partial || body.title !== undefined) {
    if (!title) errors.push("title");
  }
  if (!partial || body.areaSqm !== undefined) {
    if (!areaSqm) errors.push("areaSqm");
  }
  if (bankSettlementAmount !== undefined && bankSettlementAmount < 0) {
    errors.push("bankSettlementAmount");
  }
  if (body.bankSettlementMode !== undefined && !bankSettlementMode) {
    errors.push("bankSettlementMode");
  }
  if (body.paymentMethod !== undefined && !paymentMethod) {
    errors.push("paymentMethod");
  }
  if (!partial || body.phone !== undefined) {
    if (!phone) errors.push("phone");
  }
  if (!partial || body.price !== undefined) {
    if (price == null || price < 0) errors.push("price");
  }
  const furnishedValue = furnished ?? false;
  if (
    (furnishedValue || body.furnished === true) &&
    body.furnishingDescription !== undefined &&
    !furnishingDescription
  ) {
    errors.push("furnishingDescription");
  }
  if ((furnishedValue || body.furnished === true) && !partial && !furnishingDescription) {
    errors.push("furnishingDescription");
  }
  if (body.detailsJson !== undefined && detailsJson === null) {
    errors.push("detailsJson");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      purpose,
      title,
      description: description ?? null,
      areaSqm,
      bankSettlementAmount: bankSettlementAmount ?? 0,
      bankSettlementMode: bankSettlementMode ?? (partial ? undefined : "none"),
      paymentMethod: paymentMethod ?? (partial ? undefined : "cash"),
      furnished: furnishedValue,
      furnishingDescription: furnishingDescription ?? null,
      phone,
      price: price ?? 0,
      city: city ?? null,
      block: block ?? null,
      buildingNumber: buildingNumber ?? null,
      apartmentNumber: apartmentNumber ?? null,
      roomsCount,
      bathroomsCount,
      floorNumber,
      detailsJson: detailsJson ?? (partial ? undefined : {}),
    },
  };
}

export function validateCreateListingBody(body = {}) {
  return parseListingPayload(body, { partial: false });
}

export function validateUpdateListingBody(body = {}) {
  const out = parseListingPayload(body, { partial: true });
  const hasAny =
    body.purpose !== undefined ||
    body.title !== undefined ||
    body.description !== undefined ||
    body.areaSqm !== undefined ||
    body.bankSettlementAmount !== undefined ||
    body.bankSettlementMode !== undefined ||
    body.paymentMethod !== undefined ||
    body.furnished !== undefined ||
    body.furnishingDescription !== undefined ||
    body.phone !== undefined ||
    body.price !== undefined ||
    body.city !== undefined ||
    body.block !== undefined ||
    body.buildingNumber !== undefined ||
    body.apartmentNumber !== undefined ||
    body.roomsCount !== undefined ||
    body.bathroomsCount !== undefined ||
    body.floorNumber !== undefined ||
    body.detailsJson !== undefined;
  if (!hasAny) out.errors.push("empty_update");
  out.ok = out.errors.length === 0;
  return out;
}

export function validateMarkListingStatusBody(body = {}) {
  const errors = [];
  const nextStatus = normalizeStatus(body.nextStatus);
  const note = toTrimmedString(body.note, 2000);
  if (!["sold", "rented", "archived", "active"].includes(nextStatus)) {
    errors.push("nextStatus");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      nextStatus,
      note,
    },
  };
}

export function validateAdminReviewBody(body = {}) {
  const errors = [];
  const reviewNote = toTrimmedString(body.reviewNote, 2000);
  if (
    body.reviewNote !== undefined &&
    body.reviewNote !== null &&
    body.reviewNote !== "" &&
    !reviewNote
  ) {
    errors.push("reviewNote");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      reviewNote,
    },
  };
}
