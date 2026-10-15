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
    metadata: {
      ...(defaults?.metadata || {}),
      ...(row?.metadata || row?.metadata_json || {}),
    },
  };
  const configuredStatus = normalizeSectionStatus(merged?.status);
  const status = resolveEffectiveStatus(merged, configuredStatus);
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
    effectiveMessage: buildEffectiveMessage(merged, status),
  };
}

function parseClock(value, fallback) {
  const raw = String(value || "");
  const match = /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(raw) ? raw : fallback;
  const [hour, minute] = match.split(":").map(Number);
  return hour * 60 + minute;
}

function baghdadMinutes(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Baghdad",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const hour = Number(parts.find((part) => part.type === "hour")?.value || 0);
  const minute = Number(parts.find((part) => part.type === "minute")?.value || 0);
  return hour * 60 + minute;
}

function baghdadDateParts(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Baghdad",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  return {
    year: Number(parts.find((part) => part.type === "year")?.value || 0),
    month: Number(parts.find((part) => part.type === "month")?.value || 0),
    day: Number(parts.find((part) => part.type === "day")?.value || 0),
  };
}

function nextScheduleCloseIso(schedule, now = new Date()) {
  const closeMinutes = parseClock(schedule?.closeTime, "00:00");
  const currentMinutes = baghdadMinutes(now);
  const parts = baghdadDateParts(now);
  if (!parts.year || !parts.month || !parts.day) return null;

  const closeDateUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    Math.floor(closeMinutes / 60),
    closeMinutes % 60
  );
  const closesLaterToday = closeMinutes > currentMinutes;
  const closeAt = new Date(closeDateUtc - 3 * 60 * 60 * 1000);
  if (!closesLaterToday) {
    closeAt.setUTCDate(closeAt.getUTCDate() + 1);
  }
  return closeAt.toISOString();
}

function updatedTodayInBaghdad(value, now = new Date()) {
  const updatedAt = new Date(value || "");
  if (!Number.isFinite(updatedAt.getTime())) return false;
  const current = baghdadDateParts(now);
  const updated = baghdadDateParts(updatedAt);
  return (
    current.year === updated.year &&
    current.month === updated.month &&
    current.day === updated.day
  );
}

function isWithinSchedule(schedule, now = new Date()) {
  if (!schedule || typeof schedule !== "object") return true;
  const open = parseClock(schedule.openTime, "08:00");
  const close = parseClock(schedule.closeTime, "00:00");
  const current = baghdadMinutes(now);
  return open < close
    ? current >= open && current < close
    : current >= open || current < close;
}

function resolveEffectiveStatus(entry, configuredStatus) {
  if (configuredStatus !== "open") return configuredStatus;
  const schedule = entry?.metadata?.schedule;
  const manualOverrideUntil = Date.parse(
    String(schedule?.manualOverrideUntil || "")
  );
  if (Number.isFinite(manualOverrideUntil) && manualOverrideUntil > Date.now()) {
    return "open";
  }
  // Backward compatibility for a manual open saved before the override field
  // existed: an entry updated to open today stays open until the daily close.
  if (
    entry?.updatedAt &&
    updatedTodayInBaghdad(entry.updatedAt) &&
    !isWithinSchedule(schedule)
  ) {
    return "open";
  }
  return schedule && !isWithinSchedule(schedule)
    ? "temporarily_closed"
    : "open";
}

function buildEffectiveMessage(entry, status) {
  const custom = String(entry?.userMessage || "").trim();
  if (custom) return custom;
  if (status === "temporarily_closed" && entry?.metadata?.schedule) {
    return `This section is closed now and opens at ${entry.metadata.schedule.openTime || "08:00"} Baghdad time.`;
  }
  return SECTION_DEFAULT_MESSAGES[status] || null;
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
  if (sectionKey != null && String(sectionKey).trim().length > 0) {
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
  const status = normalizeSectionStatus(dto.status);
  const defaultSection = getDefaultSectionDefinition(key, { surfaceScope: scope });
  const displayName = String(dto.displayName || defaultSection?.displayName || "")
    .trim();
  if (!displayName) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["displayName"] },
    });
  }
  const metadata = {
    ...(dto.metadata || defaultSection?.metadata || {}),
  };
  const schedule =
    metadata.schedule && typeof metadata.schedule === "object"
      ? { ...metadata.schedule }
      : null;
  if (status === "open" && schedule) {
    schedule.manualOverrideUntil = nextScheduleCloseIso(schedule);
    metadata.schedule = schedule;
  } else if (schedule) {
    delete schedule.manualOverrideUntil;
    metadata.schedule = schedule;
  }

  const row = await repo.upsertSectionAvailability({
    sectionKey: key,
    displayName,
    parentSectionKey:
      dto.parentSectionKey == null || !String(dto.parentSectionKey).trim()
        ? defaultSection?.parentSectionKey || null
        : String(dto.parentSectionKey).trim().toLowerCase(),
    surfaceScope: scope,
    status,
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
    metadata,
    actorUserId,
  });
  return buildAvailabilityEntry(row);
}
