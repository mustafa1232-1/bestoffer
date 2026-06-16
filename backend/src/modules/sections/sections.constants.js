export const SECTION_AVAILABILITY_STATUSES = [
  "open",
  "coming_soon",
  "maintenance",
  "temporarily_closed",
];

export const SECTION_SURFACE_SCOPES = ["user"];

export const USER_APP_SECTION_DEFINITIONS = [
  { sectionKey: "shopping", displayName: "التسوق", sortOrder: 10 },
  { sectionKey: "taxi", displayName: "التكسي", sortOrder: 20 },
  { sectionKey: "services", displayName: "الخدمات", sortOrder: 30 },
  { sectionKey: "pharmacy", displayName: "الصيدلية", sortOrder: 40 },
  { sectionKey: "community", displayName: "المجتمع", sortOrder: 50 },
  { sectionKey: "jobs", displayName: "الوظائف", sortOrder: 60 },
  { sectionKey: "real_estate", displayName: "العقارات", sortOrder: 70 },
  { sectionKey: "cars", displayName: "السيارات", sortOrder: 80 },
];

export const USER_APP_SECTION_KEYS = USER_APP_SECTION_DEFINITIONS.map(
  (item) => item.sectionKey
);

export const SECTION_DEFAULT_MESSAGES = {
  open: "",
  coming_soon: "هذا القسم سيفتح قريبًا.",
  maintenance: "هذا القسم مغلق حاليًا للصيانة.",
  temporarily_closed: "هذا القسم مغلق حاليًا وسيُفتح قريبًا.",
};

export function normalizeSectionStatus(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return SECTION_AVAILABILITY_STATUSES.includes(normalized)
    ? normalized
    : "open";
}

export function normalizeSurfaceScope(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return SECTION_SURFACE_SCOPES.includes(normalized) ? normalized : "user";
}

export function isSectionOpen(value) {
  return normalizeSectionStatus(value) === "open";
}

export function listDefaultSectionsForSurface(surfaceScope = "user") {
  const scope = normalizeSurfaceScope(surfaceScope);
  if (scope !== "user") {
    return [];
  }
  return USER_APP_SECTION_DEFINITIONS.map((item) => ({
    ...item,
    surfaceScope: scope,
    parentSectionKey: null,
    status: "open",
    isVisible: true,
    userMessage: null,
    allowExistingActiveAccess: true,
    metadata: {},
  }));
}

export function getDefaultSectionDefinition(
  sectionKey,
  { surfaceScope = "user" } = {}
) {
  const normalized = String(sectionKey || "").trim().toLowerCase();
  return listDefaultSectionsForSurface(surfaceScope).find(
    (item) => item.sectionKey === normalized
  );
}
