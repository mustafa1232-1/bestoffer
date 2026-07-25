import { AppError } from "../../shared/utils/errors.js";
import * as merchantsRepo from "./merchants.repo.js";

const BUILTIN_ACTIVITY_REGISTRY = Object.freeze([
  {
    activityType: "restaurant",
    baseType: "restaurant",
    displayNameEn: "Restaurant",
    displayNameAr: "مطعم",
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "pharmacy",
    baseType: "market",
    displayNameEn: "Pharmacy",
    displayNameAr: "صيدلية",
    hasDiscoverySubcategories: true,
    supportsChat: true,
    supportsAttachments: true,
    supportsPharmacyWorkflow: true,
    internalCategoryMode: "merchant_defined_with_templates_and_constraints",
    defaultServiceFlags: {
      acceptsPrescriptions: true,
      supportsConsultation: true,
    },
    defaultBadges: [
      "prescriptions",
      "delivery",
    ],
    isActive: true,
  },
  {
    activityType: "supermarket",
    baseType: "market",
    displayNameEn: "Supermarket",
    displayNameAr: "سوبرماركت",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "sweets_bakery",
    baseType: "restaurant",
    displayNameEn: "Sweets & Bakery",
    displayNameAr: "حلويات ومخبوزات",
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "coffee_drinks",
    baseType: "restaurant",
    displayNameEn: "Coffee & Drinks",
    displayNameAr: "قهوة ومشروبات",
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "meat_poultry",
    baseType: "market",
    displayNameEn: "Meat & Poultry",
    displayNameAr: "ملحمة ودواجن",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "seafood",
    baseType: "market",
    displayNameEn: "Seafood",
    displayNameAr: "أسماك ومأكولات بحرية",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "fruits_vegetables",
    baseType: "market",
    displayNameEn: "Fruits & Vegetables",
    displayNameAr: "خضار وفواكه",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "construction",
    baseType: "market",
    displayNameEn: "Construction & Tools",
    displayNameAr: "مواد إنشائية وعدة",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "electrical_lighting",
    baseType: "market",
    displayNameEn: "Electrical & Lighting",
    displayNameAr: "كهربائيات وإنارة",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "electronics_mobile",
    baseType: "market",
    displayNameEn: "Electronics & Mobile",
    displayNameAr: "إلكترونيات وموبايل",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "home_kitchen",
    baseType: "market",
    displayNameEn: "Home & Kitchen",
    displayNameAr: "منزل ومطبخ",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "personal_care_beauty",
    baseType: "market",
    displayNameEn: "Personal Care & Beauty",
    displayNameAr: "عناية شخصية وتجميل",
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "fashion_clothing",
    baseType: "market",
    displayNameEn: "Fashion & Clothing",
    displayNameAr: "الملابس والأزياء",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "flowers_gifts",
    baseType: "market",
    displayNameEn: "Flowers & Gifts",
    displayNameAr: "زهور وهدايا",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "stationery_office",
    baseType: "market",
    displayNameEn: "Stationery & Office",
    displayNameAr: "قرطاسية ومكتبية",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "mother_child",
    baseType: "market",
    displayNameEn: "Mother & Child",
    displayNameAr: "أم وطفل",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "pet_supplies",
    baseType: "market",
    displayNameEn: "Pet Supplies",
    displayNameAr: "مستلزمات حيوانات",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "market",
    baseType: "market",
    displayNameEn: "General Market",
    displayNameAr: "متجر عام",
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
  {
    activityType: "smoking_supplies",
    baseType: "market",
    displayNameEn: "Smoking Supplies",
    displayNameAr: "مستلزمات التدخين",
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: "merchant_defined_with_templates",
    defaultServiceFlags: {},
    defaultBadges: [],
    isActive: true,
  },
]);

const BUILTIN_DISCOVERY_OPTIONS = Object.freeze({
  pharmacy: [
    { code: "prescriptions", labelEn: "Prescriptions", labelAr: "وصفات طبية", orderIndex: 1 },
    { code: "otc", labelEn: "OTC", labelAr: "أدوية بدون وصفة", orderIndex: 2 },
    { code: "vitamins", labelEn: "Vitamins", labelAr: "فيتامينات", orderIndex: 3 },
    { code: "mom_baby", labelEn: "Mom & Baby", labelAr: "أم وطفل", orderIndex: 4 },
    { code: "medical_devices", labelEn: "Medical Devices", labelAr: "أجهزة ومستلزمات طبية", orderIndex: 5 },
    { code: "open_24h", labelEn: "24 Hours", labelAr: "24 ساعة", orderIndex: 6 },
    { code: "personal_care", labelEn: "Personal Care", labelAr: "عناية شخصية", orderIndex: 7 },
    { code: "fast_delivery", labelEn: "Fast Delivery", labelAr: "توصيل سريع", orderIndex: 8 },
  ],
  restaurant: [
    { code: "eastern", labelEn: "Eastern", labelAr: "شرقي", orderIndex: 1 },
    { code: "western", labelEn: "Western", labelAr: "غربي", orderIndex: 2 },
    { code: "grills", labelEn: "Grills", labelAr: "مشويات", orderIndex: 3 },
    { code: "burger", labelEn: "Burger", labelAr: "برغر", orderIndex: 4 },
    { code: "pizza", labelEn: "Pizza", labelAr: "بيتزا", orderIndex: 5 },
    { code: "chicken", labelEn: "Chicken", labelAr: "دجاج", orderIndex: 6 },
    { code: "mandi_madhbi", labelEn: "Mandi & Madhbi", labelAr: "مندي ومظبي", orderIndex: 7 },
    { code: "seafood", labelEn: "Seafood", labelAr: "أسماك ومأكولات بحرية", orderIndex: 8 },
    { code: "breakfast", labelEn: "Breakfast", labelAr: "فطور", orderIndex: 9 },
    { code: "pastries", labelEn: "Pastries", labelAr: "معجنات", orderIndex: 10 },
    { code: "desserts", labelEn: "Desserts", labelAr: "حلويات", orderIndex: 11 },
    { code: "juices_drinks", labelEn: "Juices & Drinks", labelAr: "عصائر ومشروبات", orderIndex: 12 },
    { code: "cafe", labelEn: "Cafe", labelAr: "كافيه", orderIndex: 13 },
    { code: "healthy_diet", labelEn: "Healthy & Diet", labelAr: "صحي ودايت", orderIndex: 14 },
    { code: "sandwiches_fast_food", labelEn: "Sandwiches & Fast Food", labelAr: "ساندويشات ووجبات سريعة", orderIndex: 15 },
  ],
  sweets_bakery: [
    { code: "eastern_sweets", labelEn: "Eastern Sweets", labelAr: "حلويات شرقية", orderIndex: 1 },
    { code: "western_sweets", labelEn: "Western Sweets", labelAr: "حلويات غربية", orderIndex: 2 },
    { code: "cakes_occasions", labelEn: "Cakes & Occasions", labelAr: "كيك ومناسبات", orderIndex: 3 },
    { code: "bakery_pastries", labelEn: "Bakery & Pastries", labelAr: "مخبوزات ومعجنات", orderIndex: 4 },
    { code: "ice_cream", labelEn: "Ice Cream", labelAr: "آيس كريم", orderIndex: 5 },
    { code: "chocolate_gifts", labelEn: "Chocolate & Gifts", labelAr: "شوكولاتة وهدايا", orderIndex: 6 },
  ],
  coffee_drinks: [
    { code: "cafe", labelEn: "Cafe", labelAr: "كافيه", orderIndex: 1 },
    { code: "juices", labelEn: "Juices", labelAr: "عصائر", orderIndex: 2 },
    { code: "specialty", labelEn: "Specialty", labelAr: "مختص", orderIndex: 3 },
    { code: "tea_hot", labelEn: "Tea & Hot Drinks", labelAr: "شاي ومشروبات ساخنة", orderIndex: 4 },
    { code: "icecream_milkshake", labelEn: "Ice Cream & Milkshake", labelAr: "آيس كريم وميلك شيك", orderIndex: 5 },
  ],
  personal_care_beauty: [
    { code: "skin_care", labelEn: "Skin Care", labelAr: "عناية بالبشرة", orderIndex: 1 },
    { code: "hair_care", labelEn: "Hair Care", labelAr: "عناية بالشعر", orderIndex: 2 },
    { code: "makeup", labelEn: "Makeup", labelAr: "مكياج", orderIndex: 3 },
    { code: "perfumes", labelEn: "Perfumes", labelAr: "عطور", orderIndex: 4 },
    { code: "mens_care", labelEn: "Men Care", labelAr: "عناية رجالية", orderIndex: 5 },
  ],
  smoking_supplies: [
    { code: "cigarettes", labelEn: "Cigarettes", labelAr: "سكائر", orderIndex: 1 },
    { code: "hookahs_accessories", labelEn: "Hookahs & Accessories", labelAr: "أراكيل وملحقاتها", orderIndex: 2 },
    { code: "electronic_hookahs", labelEn: "Electronic Hookahs", labelAr: "أراكيل إلكترونية", orderIndex: 3 },
    { code: "vapes", labelEn: "Vapes", labelAr: "فيبات", orderIndex: 4 },
  ],
});

function asNonEmptyString(value) {
  if (value == null) return null;
  const out = String(value).trim();
  return out.length ? out : null;
}

function normalizeRecord(record) {
  if (!record) return null;
  return {
    activityType: String(record.activity_type || "").trim(),
    baseType: String(record.base_type || "").trim(),
    displayNameEn: String(record.display_name_en || "").trim(),
    displayNameAr: String(record.display_name_ar || "").trim(),
    hasDiscoverySubcategories: record.has_discovery_subcategories === true,
    supportsChat: record.supports_chat === true,
    supportsAttachments: record.supports_attachments === true,
    supportsPharmacyWorkflow: record.supports_pharmacy_workflow === true,
    internalCategoryMode: String(record.internal_category_mode || "").trim(),
    defaultServiceFlags:
      record.default_service_flags_json &&
      typeof record.default_service_flags_json === "object"
        ? record.default_service_flags_json
        : {},
    defaultBadges: Array.isArray(record.default_badges_json)
      ? record.default_badges_json
      : [],
    isActive: record.is_active === true,
  };
}

function cloneFallbackActivity(item) {
  return {
    activityType: item.activityType,
    baseType: item.baseType,
    displayNameEn: item.displayNameEn,
    displayNameAr: item.displayNameAr,
    hasDiscoverySubcategories: item.hasDiscoverySubcategories === true,
    supportsChat: item.supportsChat === true,
    supportsAttachments: item.supportsAttachments === true,
    supportsPharmacyWorkflow: item.supportsPharmacyWorkflow === true,
    internalCategoryMode: item.internalCategoryMode,
    defaultServiceFlags:
      item.defaultServiceFlags && typeof item.defaultServiceFlags === "object"
        ? { ...item.defaultServiceFlags }
        : {},
    defaultBadges: Array.isArray(item.defaultBadges) ? [...item.defaultBadges] : [],
    isActive: item.isActive === true,
  };
}

function listFallbackActivities({ includeInactive = false } = {}) {
  const source = includeInactive
    ? BUILTIN_ACTIVITY_REGISTRY
    : BUILTIN_ACTIVITY_REGISTRY.filter((item) => item.isActive === true);
  return source.map(cloneFallbackActivity);
}

function getFallbackActivity(activityType, { includeInactive = false } = {}) {
  const normalized = normalizeActivityType(activityType);
  if (!normalized) return null;
  const item = BUILTIN_ACTIVITY_REGISTRY.find((entry) => entry.activityType === normalized);
  if (!item) return null;
  if (!includeInactive && item.isActive !== true) return null;
  return cloneFallbackActivity(item);
}

export function normalizeActivityType(value, fallback = null) {
  const normalized = asNonEmptyString(value)?.toLowerCase() || null;
  if (!normalized) return fallback;
  if (
    [
      "fashion",
      "clothes",
      "clothing",
      "style",
      "women_fashion",
      "men_fashion",
    ].includes(normalized)
  ) {
    return "fashion_clothing";
  }
  return normalized;
}

export function normalizeDiscoverySubcategory(value) {
  return asNonEmptyString(value)?.toLowerCase() || null;
}

export function normalizeDiscoverySubcategoryList(values) {
  if (values == null) return [];
  const source = Array.isArray(values) ? values : [values];
  const seen = new Set();
  const out = [];
  for (const item of source) {
    const normalized = normalizeDiscoverySubcategory(item);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

export function inferActivityTypeFromMerchantType(type) {
  const normalizedType = asNonEmptyString(type)?.toLowerCase();
  if (normalizedType === "restaurant") return "restaurant";
  if (normalizedType === "market") return "market";
  return "market";
}

export async function listActivityRegistry({ includeInactive = false } = {}) {
  const rows = await merchantsRepo.listStoreActivities({ includeInactive });
  const resolved = new Map();

  for (const fallback of listFallbackActivities({ includeInactive })) {
    resolved.set(fallback.activityType, fallback);
  }

  for (const row of rows.map(normalizeRecord).filter(Boolean)) {
    resolved.set(row.activityType, row);
  }

  const list = [...resolved.values()];
  list.sort((a, b) => String(a.displayNameEn || "").localeCompare(String(b.displayNameEn || "")));
  return list;
}

export async function getActivityConfig(activityType, { includeInactive = false } = {}) {
  const normalized = normalizeActivityType(activityType);
  if (!normalized) return null;
  const row = await merchantsRepo.getStoreActivityByCode(normalized);
  if (row) {
    const item = normalizeRecord(row);
    if (!includeInactive && item.isActive !== true) return null;
    return item;
  }
  return getFallbackActivity(normalized, { includeInactive });
}

export async function requireActivityConfig(activityType) {
  const item = await getActivityConfig(activityType, { includeInactive: false });
  if (!item) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { activityType: "INVALID_ACTIVITY_TYPE" } },
    });
  }
  return item;
}

export async function listDiscoveryOptions(activityType) {
  const config = await requireActivityConfig(activityType);
  if (!config.hasDiscoverySubcategories) return [];
  const fallback = BUILTIN_DISCOVERY_OPTIONS[config.activityType] || [];
  const rows = await merchantsRepo.listStoreActivityDiscoveryOptions(config.activityType);
  const resolved = new Map();

  for (let index = 0; index < fallback.length; index += 1) {
    const item = fallback[index];
    resolved.set(item.code, {
      id: -(index + 1),
      activityType: config.activityType,
      code: item.code,
      labelEn: item.labelEn,
      labelAr: item.labelAr,
      orderIndex: Number(item.orderIndex || index + 1),
      metadata: {},
    });
  }

  for (const row of rows) {
    resolved.set(String(row.code || "").trim(), {
      id: Number(row.id),
      activityType: String(row.activity_type || "").trim(),
      code: String(row.code || "").trim(),
      labelEn: String(row.label_en || "").trim(),
      labelAr: String(row.label_ar || "").trim(),
      orderIndex: Number(row.order_index || 0),
      metadata:
        row.metadata_json && typeof row.metadata_json === "object"
          ? row.metadata_json
          : {},
    });
  }

  return [...resolved.values()].sort((a, b) => a.orderIndex - b.orderIndex);
}

export async function requireValidDiscoveryOption(activityType, discoverySubcategory) {
  const selection = await requireValidDiscoverySelection(activityType, {
    discoverySubcategory,
  });
  return selection.legacyDiscoverySubcategory;
}

export async function requireValidDiscoverySelection(
  activityType,
  {
    discoverySubcategory = null,
    discoverySubcategories = null,
    discoverySelectAll = false,
  } = {}
) {
  const config = await requireActivityConfig(activityType);
  const normalizedDiscovery = normalizeDiscoverySubcategory(discoverySubcategory);
  const normalizedDiscoveryList = normalizeDiscoverySubcategoryList(
    discoverySubcategories
  );
  const normalizedSelectAll = discoverySelectAll === true;

  if (
    normalizedDiscovery &&
    !normalizedDiscoveryList.includes(normalizedDiscovery)
  ) {
    normalizedDiscoveryList.unshift(normalizedDiscovery);
  }

  if (!config.hasDiscoverySubcategories) {
    if (
      normalizedSelectAll ||
      normalizedDiscovery ||
      normalizedDiscoveryList.length > 0
    ) {
      throw new AppError("VALIDATION_ERROR", {
        status: 400,
        details: { fields: { discoverySubcategory: "DISCOVERY_SUBCATEGORY_NOT_SUPPORTED" } },
      });
    }
    return {
      discoverySelectAll: false,
      discoverySubcategories: [],
      legacyDiscoverySubcategory: null,
    };
  }

  if (normalizedSelectAll) {
    return {
      discoverySelectAll: true,
      discoverySubcategories: [],
      legacyDiscoverySubcategory: null,
    };
  }

  if (normalizedDiscoveryList.length === 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { discoverySubcategory: "DISCOVERY_SUBCATEGORY_REQUIRED" } },
    });
  }

  const options = await listDiscoveryOptions(config.activityType);
  const optionCodes = new Set(
    options.map((item) => String(item.code || "").trim().toLowerCase())
  );
  for (const code of normalizedDiscoveryList) {
    if (optionCodes.has(code)) continue;
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { discoverySubcategory: "INVALID_DISCOVERY_SUBCATEGORY" } },
    });
  }

  return {
    discoverySelectAll: false,
    discoverySubcategories: normalizedDiscoveryList,
    legacyDiscoverySubcategory: normalizedDiscoveryList[0] || null,
  };
}

export function buildMerchantCapabilities(config, payload = {}) {
  const serviceFlags =
    payload.serviceFlags && typeof payload.serviceFlags === "object"
      ? payload.serviceFlags
      : config.defaultServiceFlags;
  const badges = Array.isArray(payload.badges) ? payload.badges : config.defaultBadges;

  return {
    serviceFlags,
    badges,
    supportsChat:
      payload.supportsChat === undefined ? config.supportsChat : payload.supportsChat === true,
    supportsAttachments:
      payload.supportsAttachments === undefined
        ? config.supportsAttachments
        : payload.supportsAttachments === true,
    supportsPharmacyWorkflow:
      payload.supportsPharmacyWorkflow === undefined
        ? config.supportsPharmacyWorkflow
        : payload.supportsPharmacyWorkflow === true,
  };
}
