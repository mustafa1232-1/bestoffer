const KNOWN_CATALOG_TYPES = Object.freeze([
  "generic",
  "clothes",
  "furniture",
  "electronics",
  "restaurant",
  "grocery",
  "smoking",
  "vapes",
  "hookah",
  "supplements",
]);

const CATALOG_TYPE_ALIASES = Object.freeze({
  cloths: "clothes",
  clothes: "clothes",
  clothing: "clothes",
  fashion: "clothes",
  "ملابس": "clothes",
  "الملابس": "clothes",
  furniture: "furniture",
  اثاث: "furniture",
  "أثاث": "furniture",
  "الاثاث": "furniture",
  "الأثاث": "furniture",
  electronics: "electronics",
  electrical: "electronics",
  "الكترونيات": "electronics",
  "إلكترونيات": "electronics",
  "كهربائيات": "electronics",
  restaurant: "restaurant",
  restaurants: "restaurant",
  food: "restaurant",
  "مطعم": "restaurant",
  "مطاعم": "restaurant",
  grocery: "grocery",
  groceries: "grocery",
  supermarket: "grocery",
  smoking: "smoking",
  tobacco: "smoking",
  cigarettes: "smoking",
  cigarette: "smoking",
  smoking_supplies: "smoking",
  vape: "vapes",
  vapes: "vapes",
  "e-cigarettes": "vapes",
  ecigarettes: "vapes",
  hookah: "hookah",
  hookahs: "hookah",
  shisha: "hookah",
  arakil: "hookah",
  arakeel: "hookah",
  supplements: "supplements",
  dietary_supplements: "supplements",
  vitamins: "supplements",
  protein: "supplements",
  "بقالة": "grocery",
  "مواد غذائية": "grocery",
});

const ALLOWED_CATALOG_TYPES_BY_ACTIVITY = Object.freeze({
  restaurant: ["restaurant"],
  sweets_bakery: ["restaurant"],
  coffee_drinks: ["restaurant"],
  pharmacy: ["generic"],
  fashion_clothing: ["clothes"],
  electronics_mobile: ["electronics"],
  phone_maintenance: ["electronics"],
  phones_technology: ["electronics"],
  electrical_lighting: ["electronics"],
  supermarket: ["grocery"],
  fruits_vegetables: ["grocery"],
  meat_poultry: ["grocery"],
  seafood: ["grocery"],
  home_kitchen: ["furniture", "electronics"],
  furnishings: ["furniture"],
  dietary_supplements: ["generic", "supplements"],
  smoking_supplies: ["generic", "smoking", "vapes", "hookah"],
});

function asText(value) {
  if (value == null) return "";
  return String(value).trim();
}

export function normalizeCatalogType(value, fallback = "generic") {
  const normalized = asText(value).toLowerCase();
  if (!normalized) return fallback;
  const alias = CATALOG_TYPE_ALIASES[normalized];
  if (alias) return alias;
  if (KNOWN_CATALOG_TYPES.includes(normalized)) return normalized;
  return fallback;
}

export function inferCatalogTypeFromName(name) {
  return normalizeCatalogType(name, "generic");
}

export function resolveCategoryCatalogType(category) {
  if (!category || typeof category !== "object") return "generic";
  const explicit = normalizeCatalogType(
    category.catalog_type ?? category.catalogType,
    "generic"
  );
  if (explicit !== "generic") return explicit;
  return normalizeCatalogType(inferCatalogTypeFromName(category.name), "generic");
}

export function getAllowedCatalogTypesForActivity(activityType) {
  const normalized = asText(activityType).toLowerCase();
  const allowed = new Set();
  for (const type of ALLOWED_CATALOG_TYPES_BY_ACTIVITY[normalized] || []) {
    allowed.add(type);
  }
  return [...allowed];
}

export function getDefaultCatalogTypeForActivity(activityType) {
  return getAllowedCatalogTypesForActivity(activityType)[0] || "generic";
}

export function isCatalogTypeAllowedForActivity(activityType, catalogType) {
  const normalizedCatalogType = normalizeCatalogType(catalogType, null);
  if (!normalizedCatalogType) return false;
  const allowed = getAllowedCatalogTypesForActivity(activityType);
  if (allowed.length === 0) return normalizedCatalogType === "generic";
  return allowed.includes(normalizedCatalogType);
}

export function filterCategoriesForActivity(categories, activityType) {
  return (Array.isArray(categories) ? categories : [])
    .filter((category) =>
      isCatalogTypeAllowedForActivity(
        activityType,
        resolveCategoryCatalogType(category)
      )
    )
    .map((category) => category);
}
