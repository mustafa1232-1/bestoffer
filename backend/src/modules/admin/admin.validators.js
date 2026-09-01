function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

const allowedRoles = [
  "user",
  "owner",
  "delivery",
  "deputy_admin",
  "call_center",
  "admin",
];

export function validateAdminCreateUser(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!allowedRoles.includes(body.role)) errors.push("role");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateApproveSettlement(body) {
  const errors = [];
  if (
    body.adminNote !== undefined &&
    body.adminNote !== null &&
    (typeof body.adminNote !== "string" || body.adminNote.trim().length > 1000)
  ) {
    errors.push("adminNote");
  }
  return { ok: errors.length === 0, errors };
}

export function validateToggleMerchantDisabled(body) {
  const errors = [];
  if (typeof body.isDisabled !== "boolean") errors.push("isDisabled");
  return { ok: errors.length === 0, errors };
}

export function validateTaxiCaptainCashPaymentApprove(body) {
  const errors = [];
  const cycleDays =
    body?.cycleDays === undefined || body?.cycleDays === null
      ? 30
      : Number(body.cycleDays);

  if (!Number.isInteger(cycleDays) || cycleDays < 1 || cycleDays > 365) {
    errors.push("cycleDays");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      cycleDays,
    },
  };
}

export function validateTaxiCaptainDiscount(body) {
  const errors = [];
  const discountPercent = Number(body?.discountPercent);
  if (
    !Number.isInteger(discountPercent) ||
    discountPercent < 0 ||
    discountPercent > 100
  ) {
    errors.push("discountPercent");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      discountPercent,
    },
  };
}

export function validateTaxiAdminOverview(query = {}) {
  const errors = [];
  const allowedRideStatuses = [
    "searching", "captain_assigned", "captain_arriving", "ride_started",
    "completed", "cancelled", "expired",
  ];
  const allowedCaptainStatuses = [
    "active", "online", "offline", "near_exhaustion", "exhausted", "payment_pending",
  ];
  const status = query.status ? String(query.status).trim() : null;
  const captainStatus = query.captainStatus ? String(query.captainStatus).trim() : null;
  const search = query.q ? String(query.q).trim() : "";
  const limit = query.limit == null ? 50 : Number(query.limit);
  const offset = query.offset == null ? 0 : Number(query.offset);
  if (status && !allowedRideStatuses.includes(status)) errors.push("status");
  if (captainStatus && !allowedCaptainStatuses.includes(captainStatus)) errors.push("captainStatus");
  if (search.length > 120) errors.push("q");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");
  if (!Number.isInteger(offset) || offset < 0) errors.push("offset");
  return { ok: errors.length === 0, errors, value: { status, captainStatus, search, limit, offset } };
}

export function validateTaxiAdminCancel(body = {}) {
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  const errors = [];
  if (reason.length < 3 || reason.length > 500) errors.push("reason");
  return { ok: errors.length === 0, errors, value: { reason } };
}

export function validateTaxiCreditAdjustment(body = {}) {
  const delta = Number(body.delta);
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  const errors = [];
  if (!Number.isInteger(delta) || delta === 0 || delta < -1000 || delta > 1000) errors.push("delta");
  if (reason.length < 3 || reason.length > 500) errors.push("reason");
  return { ok: errors.length === 0, errors, value: { delta, reason } };
}

const allowedAdBoardCtaTypes = ["none", "merchant", "category", "taxi", "url"];

function parseOptionalDate(value) {
  if (value === undefined || value === null || value === "") return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

export function validateAdBoardCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body?.title, 140)) errors.push("title");
  if (!isNonEmptyString(body?.subtitle, 280)) errors.push("subtitle");
  if (!isOptionalString(body?.imageUrl, 1000)) errors.push("imageUrl");
  if (!isOptionalString(body?.badgeLabel, 40)) errors.push("badgeLabel");
  if (!isOptionalString(body?.ctaLabel, 60)) errors.push("ctaLabel");
  if (
    body?.ctaTargetType !== undefined &&
    !allowedAdBoardCtaTypes.includes(String(body.ctaTargetType))
  ) {
    errors.push("ctaTargetType");
  }
  if (!isOptionalString(body?.ctaTargetValue, 1000)) errors.push("ctaTargetValue");

  const merchantId =
    body?.merchantId === undefined || body?.merchantId === null || body?.merchantId === ""
      ? null
      : Number(body.merchantId);
  if (merchantId !== null && (!Number.isInteger(merchantId) || merchantId <= 0)) {
    errors.push("merchantId");
  }

  const priority =
    body?.priority === undefined || body?.priority === null || body?.priority === ""
      ? 100
      : Number(body.priority);
  if (!Number.isInteger(priority) || priority < -1000 || priority > 1000) {
    errors.push("priority");
  }

  const isActive =
    body?.isActive === undefined || body?.isActive === null
      ? true
      : body.isActive === true || body.isActive === "true" || body.isActive === 1;

  const startsAt = parseOptionalDate(body?.startsAt);
  if (body?.startsAt && !startsAt) errors.push("startsAt");
  const endsAt = parseOptionalDate(body?.endsAt);
  if (body?.endsAt && !endsAt) errors.push("endsAt");
  if (startsAt && endsAt && endsAt <= startsAt) errors.push("dateRange");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      title: String(body?.title || "").trim(),
      subtitle: String(body?.subtitle || "").trim(),
      imageUrl: body?.imageUrl ? String(body.imageUrl).trim() : null,
      badgeLabel: body?.badgeLabel ? String(body.badgeLabel).trim() : null,
      ctaLabel: body?.ctaLabel ? String(body.ctaLabel).trim() : null,
      ctaTargetType: body?.ctaTargetType
        ? String(body.ctaTargetType).trim()
        : merchantId
          ? "merchant"
          : "none",
      ctaTargetValue: body?.ctaTargetValue ? String(body.ctaTargetValue).trim() : null,
      merchantId,
      priority,
      isActive,
      startsAt: startsAt ? startsAt.toISOString() : null,
      endsAt: endsAt ? endsAt.toISOString() : null,
    },
  };
}

export function validateAdBoardUpdate(body) {
  const errors = [];
  const value = {};

  if (body?.title !== undefined) {
    if (!isNonEmptyString(body.title, 140)) errors.push("title");
    else value.title = String(body.title).trim();
  }
  if (body?.subtitle !== undefined) {
    if (!isNonEmptyString(body.subtitle, 280)) errors.push("subtitle");
    else value.subtitle = String(body.subtitle).trim();
  }
  if (body?.imageUrl !== undefined) {
    if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
    else value.imageUrl = body.imageUrl ? String(body.imageUrl).trim() : null;
  }
  if (body?.badgeLabel !== undefined) {
    if (!isOptionalString(body.badgeLabel, 40)) errors.push("badgeLabel");
    else value.badgeLabel = body.badgeLabel ? String(body.badgeLabel).trim() : null;
  }
  if (body?.ctaLabel !== undefined) {
    if (!isOptionalString(body.ctaLabel, 60)) errors.push("ctaLabel");
    else value.ctaLabel = body.ctaLabel ? String(body.ctaLabel).trim() : null;
  }
  if (body?.ctaTargetType !== undefined) {
    const ctaTargetType = String(body.ctaTargetType).trim();
    if (!allowedAdBoardCtaTypes.includes(ctaTargetType)) errors.push("ctaTargetType");
    else value.ctaTargetType = ctaTargetType;
  }
  if (body?.ctaTargetValue !== undefined) {
    if (!isOptionalString(body.ctaTargetValue, 1000)) errors.push("ctaTargetValue");
    else value.ctaTargetValue = body.ctaTargetValue
      ? String(body.ctaTargetValue).trim()
      : null;
  }
  if (body?.merchantId !== undefined) {
    if (body.merchantId === null || body.merchantId === "") {
      value.merchantId = null;
    } else {
      const merchantId = Number(body.merchantId);
      if (!Number.isInteger(merchantId) || merchantId <= 0) errors.push("merchantId");
      else value.merchantId = merchantId;
    }
  }
  if (body?.priority !== undefined) {
    const priority = Number(body.priority);
    if (!Number.isInteger(priority) || priority < -1000 || priority > 1000) {
      errors.push("priority");
    } else {
      value.priority = priority;
    }
  }
  if (body?.isActive !== undefined) {
    value.isActive =
      body.isActive === true || body.isActive === "true" || body.isActive === 1;
  }

  if (body?.startsAt !== undefined) {
    if (body.startsAt === null || body.startsAt === "") {
      value.startsAt = null;
    } else {
      const startsAt = parseOptionalDate(body.startsAt);
      if (!startsAt) errors.push("startsAt");
      else value.startsAt = startsAt.toISOString();
    }
  }
  if (body?.endsAt !== undefined) {
    if (body.endsAt === null || body.endsAt === "") {
      value.endsAt = null;
    } else {
      const endsAt = parseOptionalDate(body.endsAt);
      if (!endsAt) errors.push("endsAt");
      else value.endsAt = endsAt.toISOString();
    }
  }

  if (
    Object.prototype.hasOwnProperty.call(value, "startsAt") &&
    Object.prototype.hasOwnProperty.call(value, "endsAt") &&
    value.startsAt &&
    value.endsAt &&
    new Date(value.endsAt) <= new Date(value.startsAt)
  ) {
    errors.push("dateRange");
  }

  if (!Object.keys(value).length) errors.push("emptyBody");

  return { ok: errors.length === 0, errors, value };
}
