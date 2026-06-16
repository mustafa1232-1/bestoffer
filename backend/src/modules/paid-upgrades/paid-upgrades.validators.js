const allowedPlanCodes = new Set([
  "car_seller_monthly",
  "property_seller_monthly",
  "premium_monthly",
]);

const allowedRequestStatuses = new Set([
  "pending_admin_review",
  "approved",
  "rejected",
  "activated",
  "cancelled",
  "all",
]);

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

function normalizePlanCodes(raw) {
  const values = [];
  if (Array.isArray(raw)) {
    values.push(...raw);
  } else if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (trimmed.startsWith("[")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) values.push(...parsed);
      } catch {
        values.push(...trimmed.split(","));
      }
    } else {
      values.push(...trimmed.split(","));
    }
  }

  return [...new Set(values.map((item) => String(item || "").trim()).filter(Boolean))];
}

export function validateListMyRequestsQuery(query = {}) {
  const errors = [];
  const statusRaw = String(query.status || "all").trim().toLowerCase();
  const status = allowedRequestStatuses.has(statusRaw) ? statusRaw : null;
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 20;
  const offset = toPositiveInt(query.offset, { min: 0, max: 100000 }) || 0;

  if (!status) errors.push("status");
  if (query.limit !== undefined && !toPositiveInt(query.limit, { min: 1, max: 100 })) {
    errors.push("limit");
  }
  if (query.offset !== undefined && !toPositiveInt(query.offset, { min: 0, max: 100000 })) {
    errors.push("offset");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      limit,
      offset,
    },
  };
}

export function validateCreatePaidUpgradeRequests(body = {}) {
  const errors = [];
  const planCodes = normalizePlanCodes(body.planCodes ?? body.planCode);
  const activityName = toTrimmedString(body.activityName, 180);
  const activityDescription = toTrimmedString(body.activityDescription, 2000);
  const contactPhone = toTrimmedString(body.contactPhone, 32);
  const notes = toTrimmedString(body.notes, 2000);
  const requestMeta =
    body.requestMeta && typeof body.requestMeta === "object" && !Array.isArray(body.requestMeta)
      ? body.requestMeta
      : body.requestMetaJson && typeof body.requestMetaJson === "object" && !Array.isArray(body.requestMetaJson)
        ? body.requestMetaJson
        : null;

  if (!planCodes.length) {
    errors.push("planCodes");
  } else if (!planCodes.every((code) => allowedPlanCodes.has(code))) {
    errors.push("planCodes");
  }

  if (!activityName) errors.push("activityName");

  if (
    body.contactPhone !== undefined &&
    body.contactPhone !== null &&
    body.contactPhone !== "" &&
    !contactPhone
  ) {
    errors.push("contactPhone");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      planCodes,
      activityName,
      activityDescription,
      contactPhone,
      notes,
      requestMeta,
    },
  };
}

export function validatePaidUpgradeRequestId(value) {
  const parsed = toPositiveInt(value);
  if (!parsed) {
    return { ok: false, errors: ["requestId"] };
  }
  return { ok: true, value: parsed };
}

export function validateListPaidUpgradeRequestsQuery(query = {}) {
  const errors = [];
  const statusRaw = String(query.status || "pending_admin_review").trim().toLowerCase();
  const status = allowedRequestStatuses.has(statusRaw) ? statusRaw : null;
  const planCode = toTrimmedString(query.planCode, 80);
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 30;
  const offset = toPositiveInt(query.offset, { min: 0, max: 100000 }) || 0;

  if (!status) errors.push("status");
  if (planCode && !allowedPlanCodes.has(planCode)) errors.push("planCode");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      planCode: planCode || null,
      limit,
      offset,
    },
  };
}

export function validatePaidUpgradeReviewBody(body = {}) {
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

