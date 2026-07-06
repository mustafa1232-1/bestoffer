import {
  CATEGORY_SUGGESTION_STATUSES,
  OFFERING_MODERATION_STATUSES,
  PROMOTION_TYPES,
  PROVIDER_APPROVAL_STATUSES,
  QUOTE_STATUSES,
  SERVICE_BOOKING_POLICIES,
  SERVICE_EXECUTION_MODES,
  SERVICE_PROVIDER_SUBSCRIPTION_REQUEST_STATUSES,
  SERVICE_PRICING_MODELS,
  SERVICE_PRICING_UNITS,
  SERVICE_REQUEST_STATUSES,
} from './services.constants.js';

function asString(value, max = 2000) {
  if (value === undefined || value === null) return null;
  const text = String(value).trim();
  if (!text) return null;
  return text.length > max ? text.slice(0, max) : text;
}

function asInt(value, { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER } = {}) {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return null;
  if (parsed < min || parsed > max) return null;
  return parsed;
}

function asNum(value, { min = -Number.MAX_VALUE, max = Number.MAX_VALUE } = {}) {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  if (parsed < min || parsed > max) return null;
  return parsed;
}

function asBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
    if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  }
  return fallback;
}

function asBoolOrNull(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
    if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  }
  return null;
}

function asStringArray(value, { maxItems = 40, itemMax = 80 } = {}) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const item of value) {
    const text = asString(item, itemMax);
    if (!text) continue;
    if (!out.includes(text)) out.push(text);
    if (out.length >= maxItems) break;
  }
  return out;
}

function toOptionalPermissionList(value) {
  if (value === undefined || value === null || value === '') return null;
  if (Array.isArray(value)) {
    return value
      .map((entry) => (entry == null ? '' : String(entry).trim()))
      .filter(Boolean);
  }
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) {
        return parsed
          .map((entry) => (entry == null ? '' : String(entry).trim()))
          .filter(Boolean);
      }
    } catch {
      return value
        .split(',')
        .map((entry) => entry.trim())
        .filter(Boolean);
    }
  }
  if (value && typeof value === 'object') {
    if (Array.isArray(value.permissions)) {
      return value.permissions
        .map((entry) => (entry == null ? '' : String(entry).trim()))
        .filter(Boolean);
    }
    if (Array.isArray(value.permissions_json)) {
      return value.permissions_json
        .map((entry) => (entry == null ? '' : String(entry).trim()))
        .filter(Boolean);
    }
  }
  return null;
}

function normalizeSort(sort) {
  const normalized = String(sort || 'newest').trim().toLowerCase();
  if (
    [
      'newest',
      'cheapest',
      'rating_desc',
      'closest',
      'fastest_response',
      'most_completed',
    ].includes(normalized)
  ) {
    return normalized;
  }
  return null;
}

function normalizeStatus(value, allowed, fallback = null) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) return fallback;
  return allowed.includes(normalized) ? normalized : null;
}

function parseJson(value) {
  if (value && typeof value === 'object') return value;
  if (typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

export function validateServiceSearchQuery(query = {}) {
  const errors = [];
  const q = asString(query.q, 140);
  const categoryId = asInt(query.categoryId ?? query.mainCategoryId, { min: 1 });
  const subcategoryId = asInt(query.subcategoryId, { min: 1 });
  const city = asString(query.city, 120);
  const area = asString(query.area, 120);
  const minPrice = asNum(query.minPrice, { min: 0 });
  const maxPrice = asNum(query.maxPrice, { min: 0 });
  const ratingMin = asNum(query.ratingMin, { min: 0, max: 5 });
  const unit = normalizeStatus(query.pricingUnit, SERVICE_PRICING_UNITS);
  const model = normalizeStatus(query.pricingModel, SERVICE_PRICING_MODELS);
  const availableNow = asBoolOrNull(query.availableNow);
  const homeService = asBoolOrNull(query.homeService);
  const emergency = asBoolOrNull(query.emergency);
  const offersOnly = asBoolOrNull(query.offersOnly);
  const sort = normalizeSort(query.sort || 'newest');
  const limit = asInt(query.limit, { min: 1, max: 100 }) || 20;
  const offset = asInt(query.offset, { min: 0, max: 200000 }) || 0;

  if (query.minPrice != null && minPrice == null) errors.push('minPrice');
  if (query.maxPrice != null && maxPrice == null) errors.push('maxPrice');
  if (minPrice != null && maxPrice != null && maxPrice < minPrice) {
    errors.push('priceRange');
  }
  if (query.ratingMin != null && ratingMin == null) errors.push('ratingMin');
  if (query.pricingUnit != null && unit == null) errors.push('pricingUnit');
  if (query.pricingModel != null && model == null) errors.push('pricingModel');
  if (!sort) errors.push('sort');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      q,
      categoryId,
      subcategoryId,
      city,
      area,
      minPrice,
      maxPrice,
      ratingMin,
      unit,
      model,
      availableNow,
      homeService,
      emergency,
      offersOnly,
      sort: sort || 'newest',
      limit,
      offset,
    },
  };
}

export function validateProviderRegisterBody(body = {}) {
  const errors = [];
  const fullName = asString(body.fullName, 120);
  const phone = asString(body.phone, 24);
  const pin = asString(body.pin, 12);
  const businessName = asString(body.businessName ?? body.providerName, 180);
  const city = asString(body.city, 120);
  const area = asString(body.area, 120);
  const addressLine = asString(body.addressLine ?? body.address, 240);
  const mainCategoryId = asInt(body.mainCategoryId, { min: 1 });
  const bio = asString(body.bio, 2000);
  const whatsappPhone = asString(body.whatsappPhone, 24);
  const bookingPolicy = normalizeStatus(body.bookingPolicy, SERVICE_BOOKING_POLICIES, 'approval_required');
  const hasEmergencyService = asBool(body.hasEmergencyService, false);
  const servesAtHome = asBool(body.servesAtHome, true);
  const servesAtShop = asBool(body.servesAtShop, false);
  const servesRemote = asBool(body.servesRemote, false);
  const pricingMode = normalizeStatus(
    body.pricingMode,
    ['fixed', 'starting_from', 'inspection_required', 'custom_quote', 'mixed'],
    'mixed'
  );
  const yearsExperience = asInt(body.yearsExperience, { min: 0, max: 70 });
  const hasTeam = asBool(body.hasTeam, false);
  const teamSize = asInt(body.teamSize, { min: 0, max: 1000 });
  const acceptsCash = asBool(body.acceptsCash, true);
  const acceptsElectronic = asBool(body.acceptsElectronic, false);
  const averageResponseMinutes = asInt(body.averageResponseMinutes, { min: 0, max: 10080 });
  const available247 = asBool(body.available247, false);
  const providerGender = normalizeStatus(body.providerGender, ['male', 'female', 'mixed', 'not_applicable']);
  const languages = asStringArray(body.languages, { maxItems: 12, itemMax: 40 });
  const areas = Array.isArray(body.areas) ? body.areas : [];
  const availabilityRules = Array.isArray(body.availabilityRules) ? body.availabilityRules : [];

  if (!fullName) errors.push('fullName');
  if (!phone) errors.push('phone');
  if (!pin || !/^\d{4,8}$/.test(pin)) errors.push('pin');
  if (!businessName) errors.push('businessName');
  if (!city) errors.push('city');
  if (!mainCategoryId) errors.push('mainCategoryId');
  if (!bookingPolicy) errors.push('bookingPolicy');
  if (!pricingMode) errors.push('pricingMode');
  if (!servesAtHome && !servesAtShop && !servesRemote) {
    errors.push('executionModes');
  }

  const normalizedAreas = areas
    .map((item) => ({
      city: asString(item?.city, 120),
      area: asString(item?.area, 120),
      note: asString(item?.note, 200),
    }))
    .filter((item) => item.city);

  const normalizedRules = availabilityRules
    .map((item) => ({
      dayOfWeek: asInt(item?.dayOfWeek, { min: 0, max: 6 }),
      startTime: asString(item?.startTime, 8),
      endTime: asString(item?.endTime, 8),
      isActive: asBool(item?.isActive, true),
    }))
    .filter((item) => item.dayOfWeek != null && item.startTime && item.endTime);

  return {
    ok: errors.length === 0,
    errors,
    value: {
      fullName,
      phone,
      pin,
      businessName,
      city,
      area,
      addressLine,
      mainCategoryId,
      bio,
      whatsappPhone,
      bookingPolicy,
      hasEmergencyService,
      servesAtHome,
      servesAtShop,
      servesRemote,
      pricingMode,
      yearsExperience,
      hasTeam,
      teamSize,
      acceptsCash,
      acceptsElectronic,
      averageResponseMinutes,
      available247,
      providerGender,
      languages,
      areas: normalizedAreas,
      availabilityRules: normalizedRules,
    },
  };
}

export function validateProviderSubscriptionStatusBody(body = {}) {
  const errors = [];
  const phone = asString(body.phone, 24);
  const pin = asString(body.pin, 12);
  if (!phone) errors.push('phone');
  if (!pin || !/^\d{4,8}$/.test(pin)) errors.push('pin');
  return {
    ok: errors.length === 0,
    errors,
    value: { phone, pin },
  };
}

export function validateProviderSubscriptionOfferResponseBody(body = {}) {
  const errors = [];
  const action = normalizeStatus(body.action, ['accept', 'reject']);
  const note = asString(body.note, 1000);
  const offerId = asInt(body.offerId, { min: 1 });
  if (!action) errors.push('action');
  return {
    ok: errors.length === 0,
    errors,
    value: {
      action,
      note,
      offerId,
    },
  };
}

export function validateAdminSubscriptionOfferBody(body = {}) {
  const errors = [];
  const amount = asNum(body.amount, { min: 0 });
  const currency = asString(body.currency, 8) || 'IQD';
  const title = asString(body.title, 160);
  const description = asString(body.description, 1200);
  const validUntil = asString(body.validUntil, 64);
  const note = asString(body.note, 1000);
  if (amount == null) errors.push('amount');
  return {
    ok: errors.length === 0,
    errors,
    value: {
      amount,
      currency,
      title,
      description,
      validUntil,
      note,
    },
  };
}

export function validateAdminSubscriptionRejectBody(body = {}) {
  const note = asString(body.note, 1000);
  return {
    ok: true,
    errors: [],
    value: { note },
  };
}

export function validateAdminCashConfirmationBody(body = {}) {
  const note = asString(body.note, 1000);
  return {
    ok: true,
    errors: [],
    value: { note },
  };
}

export function validateProviderProfileUpdateBody(body = {}) {
  const base = validateProviderRegisterBody({
    ...body,
    fullName: body.fullName || 'placeholder',
    phone: body.phone || '0000000000',
    pin: body.pin || '0000',
    businessName: body.businessName || body.providerName || 'placeholder',
    city: body.city || 'placeholder',
    mainCategoryId: body.mainCategoryId || 1,
  });

  return {
    ok: true,
    errors: [],
    value: {
      ...base.value,
      fullName: undefined,
      phone: undefined,
      pin: undefined,
    },
  };
}

export function validateProviderEmployeeInviteBody(body = {}) {
  const errors = [];
  const fullName = asString(body.fullName, 180);
  const phone = asString(body.phone, 32);
  const pin = asString(body.pin, 12);
  const roleTag = asString(body.roleTag ?? 'staff', 80) || 'staff';
  const displayName = asString(body.displayName, 180);
  const contactEmail = asString(body.contactEmail, 320);
  const permissions = toOptionalPermissionList(body.permissions);
  const isActive = asBoolOrNull(body.isActive);
  const archivedAt = asString(body.archivedAt, 64);
  const notes = asString(body.notes, 3000);
  const reason = asString(body.reason, 3000);

  if (!fullName) errors.push('fullName');
  if (!phone) errors.push('phone');
  if (!pin || !/^\d{4,8}$/.test(pin)) errors.push('pin');
  if (body.isActive !== undefined && isActive == null) errors.push('isActive');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      fullName,
      phone,
      pin,
      roleTag,
      displayName,
      contactEmail,
      permissions,
      isActive: isActive ?? true,
      archivedAt,
      notes,
      reason,
    },
  };
}

export function validateProviderEmployeeUpsertBody(body = {}) {
  const errors = [];
  const employeeUserId = asInt(body.employeeUserId, { min: 1 });
  const roleTag = asString(body.roleTag ?? 'staff', 80) || 'staff';
  const displayName = asString(body.displayName, 180);
  const contactEmail = asString(body.contactEmail, 320);
  const permissions = toOptionalPermissionList(body.permissions);
  const isActive = asBoolOrNull(body.isActive);
  const archivedAt = asString(body.archivedAt, 64);
  const notes = asString(body.notes, 3000);
  const reason = asString(body.reason, 3000);

  if (!employeeUserId) errors.push('employeeUserId');
  if (body.isActive !== undefined && isActive == null) errors.push('isActive');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      employeeUserId,
      roleTag,
      displayName,
      contactEmail,
      permissions,
      isActive: isActive ?? true,
      archivedAt,
      notes,
      reason,
    },
  };
}

export function validateProviderEmployeeActivityLogQuery(query = {}) {
  const errors = [];
  const employeeUserId = asInt(query.employeeUserId, { min: 1 });
  const limit = asInt(query.limit, { min: 1, max: 200 }) || 120;
  if (query.employeeUserId != null && employeeUserId == null) {
    errors.push('employeeUserId');
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      employeeUserId,
      limit,
    },
  };
}

function normalizePricingOption(item = {}) {
  const pricingModel = normalizeStatus(item.pricingModel, SERVICE_PRICING_MODELS);
  const pricingUnit = normalizeStatus(item.pricingUnit, SERVICE_PRICING_UNITS);
  return {
    pricingModel,
    pricingUnit,
    label: asString(item.label, 120),
    amount: asNum(item.amount, { min: 0 }),
    minAmount: asNum(item.minAmount, { min: 0 }),
    maxAmount: asNum(item.maxAmount, { min: 0 }),
    visitFee: asNum(item.visitFee, { min: 0 }),
    currency: asString(item.currency, 8) || 'IQD',
    minQuantity: asNum(item.minQuantity, { min: 0 }),
    maxQuantity: asNum(item.maxQuantity, { min: 0 }),
    inspectionRequired: asBool(item.inspectionRequired, false),
    notes: asString(item.notes, 600),
    isDefault: asBool(item.isDefault, false),
    isActive: asBool(item.isActive, true),
    sortOrder: asInt(item.sortOrder, { min: 0, max: 9999 }) || 0,
  };
}

export function validateOfferingBody(body = {}, { partial = false } = {}) {
  const errors = [];
  const name = asString(body.name, 180);
  const description = asString(body.description, 4000);
  const mainCategoryId = asInt(body.mainCategoryId, { min: 1 });
  const subcategoryId = asInt(body.subcategoryId, { min: 1 });
  const executionMode = normalizeStatus(body.executionMode, SERVICE_EXECUTION_MODES, 'both');
  const requiresSchedule = asBool(body.requiresSchedule, true);
  const requiresProviderApproval = asBool(body.requiresProviderApproval, true);
  const estimatedDurationMinutes = asInt(body.estimatedDurationMinutes, { min: 1, max: 10080 });
  const hasFixedPrice = asBool(body.hasFixedPrice, false);
  const startsFromPrice = asNum(body.startsFromPrice, { min: 0 });
  const inspectionRequired = asBool(body.inspectionRequired, false);
  const customQuoteOnly = asBool(body.customQuoteOnly, false);
  const workersCount = asInt(body.workersCount, { min: 1, max: 1000 });
  const includesText = asString(body.includesText, 2000);
  const excludesText = asString(body.excludesText, 2000);
  const materialsText = asString(body.materialsText, 2000);
  const notes = asString(body.notes, 2000);
  const supportsHourlyBooking = asBool(body.supportsHourlyBooking, false);
  const supportsDailyBooking = asBool(body.supportsDailyBooking, false);
  const supportsVisitBooking = asBool(body.supportsVisitBooking, true);
  const supportsFullDayBooking = asBool(body.supportsFullDayBooking, false);
  const searchText = asString(body.searchText, 1000);
  const pricingOptionsRaw = Array.isArray(body.pricingOptions) ? body.pricingOptions : [];
  const pricingOptions = pricingOptionsRaw.map(normalizePricingOption);

  if (!partial && !name) errors.push('name');
  if (!partial && !mainCategoryId) errors.push('mainCategoryId');
  if (!partial && !subcategoryId) errors.push('subcategoryId');
  if (body.executionMode != null && !executionMode) errors.push('executionMode');

  let hasDefault = false;
  for (let index = 0; index < pricingOptions.length; index += 1) {
    const option = pricingOptions[index];
    if (!option.pricingModel) {
      errors.push(`pricingOptions.${index}.pricingModel`);
    }
    if (!option.pricingUnit) {
      errors.push(`pricingOptions.${index}.pricingUnit`);
    }
    if (!['inspection_required', 'custom_quote'].includes(option.pricingModel || '') && option.amount == null) {
      errors.push(`pricingOptions.${index}.amount`);
    }
    if (option.minAmount != null && option.maxAmount != null && option.maxAmount < option.minAmount) {
      errors.push(`pricingOptions.${index}.amountRange`);
    }
    if (option.isDefault) hasDefault = true;
  }
  if (pricingOptions.length > 0 && !hasDefault) {
    pricingOptions[0].isDefault = true;
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      name,
      description,
      mainCategoryId,
      subcategoryId,
      executionMode: executionMode || 'both',
      requiresSchedule,
      requiresProviderApproval,
      estimatedDurationMinutes,
      hasFixedPrice,
      startsFromPrice,
      inspectionRequired,
      customQuoteOnly,
      workersCount,
      includesText,
      excludesText,
      materialsText,
      notes,
      supportsHourlyBooking,
      supportsDailyBooking,
      supportsVisitBooking,
      supportsFullDayBooking,
      searchText,
      pricingOptions,
    },
  };
}

export function validatePromotionBody(body = {}) {
  const errors = [];
  const title = asString(body.title, 160);
  const description = asString(body.description, 1200);
  const discountType = normalizeStatus(body.discountType, PROMOTION_TYPES);
  const discountValue = asNum(body.discountValue, { min: 0 });
  const specialPrice = asNum(body.specialPrice, { min: 0 });
  const startsAt = asString(body.startsAt, 64);
  const endsAt = asString(body.endsAt, 64);
  const badgeColor = asString(body.badgeColor, 32);
  const offeringIds = asStringArray(body.offeringIds, { maxItems: 60, itemMax: 30 })
    .map((item) => asInt(item, { min: 1 }))
    .filter((item) => item != null);

  if (!title) errors.push('title');
  if (!discountType) errors.push('discountType');
  if (!startsAt) errors.push('startsAt');
  if (!endsAt) errors.push('endsAt');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      title,
      description,
      discountType,
      discountValue,
      specialPrice,
      startsAt,
      endsAt,
      badgeColor,
      offeringIds,
    },
  };
}

export function validatePortfolioBody(body = {}) {
  const errors = [];
  const title = asString(body.title, 180);
  const description = asString(body.description, 1200);
  const offeringId = asInt(body.offeringId, { min: 1 });
  const mediaKind = normalizeStatus(body.mediaKind, ['image', 'video'], 'image');
  const beforeMediaUrl = asString(body.beforeMediaUrl, 2000);
  const afterMediaUrl = asString(body.afterMediaUrl, 2000);
  const sortOrder = asInt(body.sortOrder, { min: 0, max: 10000 }) || 0;
  const isPinned = asBool(body.isPinned, false);

  if (body.mediaKind != null && !mediaKind) errors.push('mediaKind');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      title,
      description,
      offeringId,
      mediaKind: mediaKind || 'image',
      beforeMediaUrl,
      afterMediaUrl,
      sortOrder,
      isPinned,
    },
  };
}

export function validateCategorySuggestionBody(body = {}) {
  const errors = [];
  const name = asString(body.name, 120);
  const suggestionType = normalizeStatus(body.suggestionType, ['main', 'sub']);
  const parentCategoryId = asInt(body.parentCategoryId, { min: 1 });
  const details = asString(body.details, 1000);

  if (!name) errors.push('name');
  if (!suggestionType) errors.push('suggestionType');
  if (suggestionType === 'sub' && !parentCategoryId) errors.push('parentCategoryId');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      name,
      suggestionType,
      parentCategoryId,
      details,
    },
  };
}

export function validateServiceRequestBody(body = {}) {
  const errors = [];
  const offeringId = asInt(body.offeringId, { min: 1 });
  const providerId = asInt(body.providerId, { min: 1 });
  const pricingOptionId = asInt(body.pricingOptionId, { min: 1 });
  const requestedExecutionMode = normalizeStatus(body.requestedExecutionMode, SERVICE_EXECUTION_MODES);
  const requestedDate = asString(body.requestedDate, 20);
  const requestedTime = asString(body.requestedTime, 20);
  const quantity = asNum(body.quantity, { min: 0 });
  const durationHours = asNum(body.durationHours, { min: 0 });
  const notes = asString(body.notes, 2000);
  const addressLine = asString(body.addressLine, 300);
  const city = asString(body.city, 120);
  const area = asString(body.area, 120);
  const latitude = asNum(body.latitude, { min: -90, max: 90 });
  const longitude = asNum(body.longitude, { min: -180, max: 180 });
  const requiresHomeService = asBool(body.requiresHomeService, false);
  const requiresQuote = asBool(body.requiresQuote, false);

  if (!offeringId) errors.push('offeringId');
  if (!providerId) errors.push('providerId');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      offeringId,
      providerId,
      pricingOptionId,
      requestedExecutionMode,
      requestedDate,
      requestedTime,
      quantity,
      durationHours,
      notes,
      addressLine,
      city,
      area,
      latitude,
      longitude,
      requiresHomeService,
      requiresQuote,
    },
  };
}

export function validateQuoteBody(body = {}) {
  const errors = [];
  const pricingModel = normalizeStatus(body.pricingModel, SERVICE_PRICING_MODELS);
  const pricingUnit = normalizeStatus(body.pricingUnit, SERVICE_PRICING_UNITS);
  const amount = asNum(body.amount, { min: 0 });
  const minAmount = asNum(body.minAmount, { min: 0 });
  const maxAmount = asNum(body.maxAmount, { min: 0 });
  const visitFee = asNum(body.visitFee, { min: 0 });
  const currency = asString(body.currency, 8) || 'IQD';
  const inspectionRequired = asBool(body.inspectionRequired, false);
  const proposedVisitAt = asString(body.proposedVisitAt, 64);
  const proposedStartAt = asString(body.proposedStartAt, 64);
  const proposedEndAt = asString(body.proposedEndAt, 64);
  const note = asString(body.note, 1000);
  const expiresAt = asString(body.expiresAt, 64);

  if (!pricingModel) errors.push('pricingModel');
  if (!pricingUnit) errors.push('pricingUnit');
  if (!['inspection_required', 'custom_quote'].includes(pricingModel || '') && amount == null) {
    errors.push('amount');
  }
  if (minAmount != null && maxAmount != null && maxAmount < minAmount) {
    errors.push('amountRange');
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      pricingModel,
      pricingUnit,
      amount,
      minAmount,
      maxAmount,
      visitFee,
      currency,
      inspectionRequired,
      proposedVisitAt,
      proposedStartAt,
      proposedEndAt,
      note,
      expiresAt,
    },
  };
}

export function validateRequestStatusBody(body = {}, { providerFlow = false } = {}) {
  const allowed = providerFlow
    ? ['accepted', 'scheduled', 'in_progress', 'completed', 'rejected', 'cancelled', 'awaiting_provider']
    : ['cancelled', 'completed'];
  const errors = [];
  const status = normalizeStatus(body.status ?? body.nextStatus, allowed);
  const note = asString(body.note, 1000);
  const scheduledStartAt = asString(body.scheduledStartAt, 64);
  const scheduledEndAt = asString(body.scheduledEndAt, 64);

  if (!status) errors.push('status');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      note,
      scheduledStartAt,
      scheduledEndAt,
    },
  };
}

export function validateQuoteResponseBody(body = {}) {
  const errors = [];
  const action = normalizeStatus(body.action, ['accepted', 'rejected']);
  const note = asString(body.note, 800);
  if (!action) errors.push('action');
  return {
    ok: errors.length === 0,
    errors,
    value: {
      action,
      note,
    },
  };
}

export function validateReviewBody(body = {}) {
  const errors = [];
  const requestId = asInt(body.requestId, { min: 1 });
  const rating = asInt(body.rating, { min: 1, max: 5 });
  const comment = asString(body.comment, 2000);
  const serviceAsDescribed = asBoolOrNull(body.serviceAsDescribed);
  const onTime = asBoolOrNull(body.onTime);
  const priceFair = asBoolOrNull(body.priceFair);
  const recommend = asBoolOrNull(body.recommend);
  const imageUrls = asStringArray(body.imageUrls, { maxItems: 8, itemMax: 2000 });

  if (!requestId) errors.push('requestId');
  if (!rating) errors.push('rating');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      requestId,
      rating,
      comment,
      serviceAsDescribed,
      onTime,
      priceFair,
      recommend,
      imageUrls,
    },
  };
}

export function validateAdminCategoryReviewBody(body = {}) {
  const errors = [];
  const action = normalizeStatus(body.action, ['approved', 'rejected', 'merged']);
  const reviewNote = asString(body.reviewNote, 1000);
  const mergeTargetCategoryId = asInt(body.mergeTargetCategoryId, { min: 1 });

  if (!action) errors.push('action');
  if (action === 'merged' && !mergeTargetCategoryId) errors.push('mergeTargetCategoryId');

  return {
    ok: errors.length === 0,
    errors,
    value: {
      action,
      reviewNote,
      mergeTargetCategoryId,
    },
  };
}

export function validateAdminProviderStatusBody(body = {}) {
  const errors = [];
  const status = normalizeStatus(body.status, PROVIDER_APPROVAL_STATUSES);
  const note = asString(body.note, 1000);
  if (!status) errors.push('status');
  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      note,
    },
  };
}

export function validateAdminOfferingStatusBody(body = {}) {
  const errors = [];
  const status = normalizeStatus(body.status, OFFERING_MODERATION_STATUSES);
  const note = asString(body.note, 1000);
  if (!status) errors.push('status');
  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      note,
    },
  };
}

export function validatePaginationQuery(query = {}) {
  const limit = asInt(query.limit, { min: 1, max: 100 }) || 20;
  const offset = asInt(query.offset, { min: 0, max: 200000 }) || 0;
  return {
    ok: true,
    errors: [],
    value: { limit, offset },
  };
}

export function validateIdParam(value, field = 'id') {
  const id = asInt(value, { min: 1 });
  return {
    ok: id != null,
    errors: id == null ? [field] : [],
    value: id,
  };
}

export function validateModerationStatusQuery(query = {}) {
  const providerStatus = normalizeStatus(query.providerStatus, PROVIDER_APPROVAL_STATUSES);
  const offeringStatus = normalizeStatus(query.offeringStatus, OFFERING_MODERATION_STATUSES);
  const categorySuggestionStatus = normalizeStatus(query.categorySuggestionStatus, CATEGORY_SUGGESTION_STATUSES);
  const requestStatus = normalizeStatus(query.requestStatus, SERVICE_REQUEST_STATUSES);
  const subscriptionRequestStatus = normalizeStatus(
    query.subscriptionRequestStatus,
    SERVICE_PROVIDER_SUBSCRIPTION_REQUEST_STATUSES
  );
  const quoteStatus = normalizeStatus(query.quoteStatus, QUOTE_STATUSES);
  return {
    ok: true,
    errors: [],
    value: {
      providerStatus,
      offeringStatus,
      categorySuggestionStatus,
      requestStatus,
      subscriptionRequestStatus,
      quoteStatus,
    },
  };
}

export function parseJsonPayload(value) {
  return parseJson(value);
}
