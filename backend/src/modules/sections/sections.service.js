import { AppError } from "../../shared/utils/errors.js";
import {
  getDefaultSectionDefinition,
  listDefaultSectionsForSurface,
  normalizeSectionStatus,
  normalizeSurfaceScope,
  SECTION_DEFAULT_MESSAGES,
} from "./sections.constants.js";
import * as repo from "./sections.repo.js";

function buildAvailabilityEntry(row) {
  const defaults = getDefaultSectionDefinition(row?.sectionKey, {
    surfaceScope: row?.surfaceScope || row?.surface_scope || "user",
  });
  const merged = {
    ...defaults,
    ...row,
    metadata: row?.metadata || row?.metadata_json || defaults?.metadata || {},
  };
  const status = normalizeSectionStatus(merged?.status);
  return {
    ...merged,
    status,
    isOpen: status === "open",
    badgeLabel:
      status === "open"
        ? null
        : status === "coming_soon"
        ? "قريبًا"
        : status === "maintenance"
        ? "تحت الصيانة"
        : "مغلق حاليًا",
    effectiveMessage:
      (merged?.userMessage || "").trim() ||
      SECTION_DEFAULT_MESSAGES[status] ||
      null,
  };
}

function sortAvailabilityEntries(a, b) {
  const bySort = Number(a?.sortOrder || 0) - Number(b?.sortOrder || 0);
  if (bySort !== 0) return bySort;
  return String(a?.sectionKey || "").localeCompare(String(b?.sectionKey || ""));
}

function mergeAvailabilityRows(rows, { surfaceScope = "user" } = {}) {
  const scope = normalizeSurfaceScope(surfaceScope);
  const resolved = new Map();
  for (const item of listDefaultSectionsForSurface(scope)) {
    const entry = buildAvailabilityEntry(item);
    resolved.set(entry.sectionKey, entry);
  }
  for (const row of rows) {
    const entry = buildAvailabilityEntry(row);
    resolved.set(entry.sectionKey, entry);
  }
  return [...resolved.values()].sort(sortAvailabilityEntries);
}

function assertValidSectionKey(value) {
  const key = String(value || "").trim().toLowerCase();
  if (!key || !/^[a-z0-9_]+$/.test(key)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["sectionKey"] },
    });
  }
  return key;
}

export async function listPublicSectionAvailability({ surfaceScope = "user" }) {
  const scope = normalizeSurfaceScope(surfaceScope);
  const rows = await repo.listSectionAvailability({ surfaceScope: scope });
  return mergeAvailabilityRows(rows, { surfaceScope: scope });
}

export async function listAdminSectionAvailability({ surfaceScope = "user" }) {
  const scope = normalizeSurfaceScope(surfaceScope);
  const rows = await repo.listSectionAvailability({ surfaceScope: scope });
  return mergeAvailabilityRows(rows, { surfaceScope: scope });
}

export async function listSectionAvailabilityAudit({
  surfaceScope = "user",
  sectionKey = null,
  limit = 80,
}) {
  if (sectionKey != null && String(sectionKey).trim().isNotEmpty) {
    assertValidSectionKey(sectionKey);
  }
  return repo.listSectionAvailabilityAudit({
    surfaceScope: normalizeSurfaceScope(surfaceScope),
    sectionKey,
    limit,
  });
}

export async function updateSectionAvailability({
  sectionKey,
  dto,
  actorUserId,
}) {
  const key = assertValidSectionKey(sectionKey);
  const scope = normalizeSurfaceScope(dto.surfaceScope || "user");
  const defaultSection = getDefaultSectionDefinition(key, { surfaceScope: scope });
  const displayName = String(dto.displayName || defaultSection?.displayName || "")
    .trim();
  if (!displayName) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["displayName"] },
    });
  }
  const row = await repo.upsertSectionAvailability({
    sectionKey: key,
    displayName,
    parentSectionKey:
      dto.parentSectionKey == null || !String(dto.parentSectionKey).trim()
        ? defaultSection?.parentSectionKey || null
        : String(dto.parentSectionKey).trim().toLowerCase(),
    surfaceScope: scope,
    status: normalizeSectionStatus(dto.status),
    isVisible: dto.isVisible !== false,
    userMessage:
      dto.userMessage == null || !String(dto.userMessage).trim()
        ? null
        : String(dto.userMessage).trim(),
    sortOrder:
      dto.sortOrder == null
        ? Number(defaultSection?.sortOrder || 0)
        : Math.max(0, Number(dto.sortOrder) || 0),
    allowExistingActiveAccess: dto.allowExistingActiveAccess !== false,
    metadata: dto.metadata || defaultSection?.metadata || {},
    actorUserId,
  });
  return buildAvailabilityEntry(row);
}
