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
  "accountant",
  "hr",
  "deputy_admin",
  "call_center",
  "admin",
];

const allowedDriverTypes = ["app_driver", "store_driver"];

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
  if (body.role === "delivery") {
    const driverType = String(body.driverType || "").trim().toLowerCase();
    if (!allowedDriverTypes.includes(driverType)) {
      errors.push("driverType");
    }

    if (driverType === "store_driver") {
      const merchantId = Number(body.merchantId);
      if (!Number.isInteger(merchantId) || merchantId <= 0) {
        errors.push("merchantId");
      }
    } else if (
      body.merchantId !== undefined &&
      body.merchantId !== null &&
      body.merchantId !== ""
    ) {
      const merchantId = Number(body.merchantId);
      if (!Number.isInteger(merchantId) || merchantId <= 0) {
        errors.push("merchantId");
      }
    }
  }

  if (body.role === "accountant" || body.role === "hr") {
    const merchantId = Number(body.merchantId);
    if (!Number.isInteger(merchantId) || merchantId <= 0) {
      errors.push("merchantId");
    }
  }

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateDeliveryDriverProfilePatch(body) {
  const errors = [];
  const driverType = String(body?.driverType || "").trim().toLowerCase();
  if (!allowedDriverTypes.includes(driverType)) {
    errors.push("driverType");
  }

  if (driverType === "store_driver") {
    const merchantId = Number(body?.merchantId);
    if (!Number.isInteger(merchantId) || merchantId <= 0) {
      errors.push("merchantId");
    }
  } else if (
    body?.merchantId !== undefined &&
    body?.merchantId !== null &&
    body?.merchantId !== ""
  ) {
    const merchantId = Number(body.merchantId);
    if (!Number.isInteger(merchantId) || merchantId <= 0) {
      errors.push("merchantId");
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      driverType,
      merchantId:
        body?.merchantId === undefined || body?.merchantId === null || body?.merchantId === ""
          ? null
          : Number(body.merchantId),
    },
  };
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

export function validateListSocialUsersQuery(query) {
  const errors = [];
  const search = String(query?.search || "").trim();
  const limitRaw = query?.limit;
  const limit =
    limitRaw === undefined || limitRaw === null || limitRaw === ""
      ? 60
      : Number(limitRaw);
  const beforeIdRaw = query?.beforeId;
  const beforeId =
    beforeIdRaw === undefined || beforeIdRaw === null || beforeIdRaw === ""
      ? null
      : Number(beforeIdRaw);

  if (search.length > 100) errors.push("search");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    errors.push("limit");
  }
  if (beforeId != null && (!Number.isInteger(beforeId) || beforeId <= 0)) {
    errors.push("beforeId");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Number.isInteger(limit) ? Math.max(1, Math.min(200, limit)) : 60,
      beforeId,
    },
  };
}

export function validateSocialUserAccountStatusPatch(body) {
  const errors = [];
  if (typeof body?.isDisabled !== "boolean") {
    errors.push("isDisabled");
  }
  const note =
    body?.note === undefined || body?.note === null ? null : String(body.note).trim();
  if (note != null && note.length > 600) {
    errors.push("note");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      isDisabled: body?.isDisabled === true,
      note: note || null,
    },
  };
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

export function validateTaxiCaptainProfileEditReview(body) {
  const errors = [];
  const adminNote =
    body?.adminNote === undefined || body?.adminNote === null
      ? null
      : String(body.adminNote).trim();

  if (adminNote != null && adminNote.length > 1200) {
    errors.push("adminNote");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      adminNote,
    },
  };
}

export function validateListSocialReportsQuery(query) {
  const errors = [];
  const limitRaw = query?.limit;
  const limit =
    limitRaw === undefined || limitRaw === null || limitRaw === ""
      ? 80
      : Number(limitRaw);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    errors.push("limit");
  }

  const beforePostIdRaw = query?.beforePostId;
  const beforePostId =
    beforePostIdRaw === undefined || beforePostIdRaw === null || beforePostIdRaw === ""
      ? null
      : Number(beforePostIdRaw);
  if (
    beforePostId != null &&
    (!Number.isInteger(beforePostId) || beforePostId <= 0)
  ) {
    errors.push("beforePostId");
  }

  const beforeIdRaw = query?.beforeId;
  const beforeId =
    beforeIdRaw === undefined || beforeIdRaw === null || beforeIdRaw === ""
      ? null
      : Number(beforeIdRaw);
  if (beforeId != null && (!Number.isInteger(beforeId) || beforeId <= 0)) {
    errors.push("beforeId");
  }

  const status = String(query?.status || "open").trim().toLowerCase();
  if (!["open", "pending_edit", "all"].includes(status)) {
    errors.push("status");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit,
      status,
      beforePostId,
      beforeId,
    },
  };
}

export function validatePostReportReview(body) {
  const errors = [];
  const action = String(body?.action || "").trim().toLowerCase();
  if (!["keep", "request_edit", "delete"].includes(action)) {
    errors.push("action");
  }
  const note =
    body?.note === undefined || body?.note === null ? null : String(body.note).trim();
  if (note != null && note.length > 2000) {
    errors.push("note");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      action,
      note,
    },
  };
}

export function validateListSocialStoryReportsQuery(query) {
  const errors = [];
  const limitRaw = query?.limit;
  const limit =
    limitRaw === undefined || limitRaw === null || limitRaw === ""
      ? 80
      : Number(limitRaw);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    errors.push("limit");
  }

  const beforeStoryIdRaw = query?.beforeStoryId;
  const beforeStoryId =
    beforeStoryIdRaw === undefined || beforeStoryIdRaw === null || beforeStoryIdRaw === ""
      ? null
      : Number(beforeStoryIdRaw);
  if (beforeStoryId != null && (!Number.isInteger(beforeStoryId) || beforeStoryId <= 0)) {
    errors.push("beforeStoryId");
  }

  const status = String(query?.status || "open").trim().toLowerCase();
  if (!["open", "pending_edit", "all"].includes(status)) {
    errors.push("status");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit,
      status,
      beforeStoryId,
    },
  };
}

export function validateListResidenceChangeRequestsQuery(query) {
  const errors = [];
  const limitRaw = query?.limit;
  const limit =
    limitRaw === undefined || limitRaw === null || limitRaw === ""
      ? 80
      : Number(limitRaw);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    errors.push("limit");
  }

  const beforeIdRaw = query?.beforeId;
  const beforeId =
    beforeIdRaw === undefined || beforeIdRaw === null || beforeIdRaw === ""
      ? null
      : Number(beforeIdRaw);
  if (beforeId != null && (!Number.isInteger(beforeId) || beforeId <= 0)) {
    errors.push("beforeId");
  }

  const status = String(query?.status || "pending").trim().toLowerCase();
  if (!["pending", "approved", "rejected", "cancelled", "all"].includes(status)) {
    errors.push("status");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit,
      status,
      beforeId,
    },
  };
}

export function validateResidenceChangeReview(body) {
  const errors = [];
  const reviewNote =
    body?.reviewNote === undefined || body?.reviewNote === null
      ? null
      : String(body.reviewNote).trim();
  if (reviewNote != null && reviewNote.length > 2000) {
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

export function validateSocialCapabilityRestrictionCreate(body) {
  const errors = [];
  const capabilityKey = String(body?.capabilityKey || body?.capability_key || "")
    .trim()
    .toLowerCase();
  const allowedKeys = [
    "post_create",
    "story_create",
    "reel_create",
    "comment_create",
    "community_post_create",
  ];
  if (!allowedKeys.includes(capabilityKey)) {
    errors.push("capabilityKey");
  }

  const reason =
    body?.reason === undefined || body?.reason === null ? null : String(body.reason).trim();
  if (reason != null && reason.length > 1000) {
    errors.push("reason");
  }

  const startsAt = parseOptionalDate(body?.startsAt);
  if (body?.startsAt && !startsAt) errors.push("startsAt");

  const endsAt = parseOptionalDate(body?.endsAt);
  if (body?.endsAt && !endsAt) errors.push("endsAt");
  if (startsAt && endsAt && endsAt <= startsAt) errors.push("dateRange");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      capabilityKey,
      reason: reason || null,
      startsAt: startsAt ? startsAt.toISOString() : null,
      endsAt: endsAt ? endsAt.toISOString() : null,
    },
  };
}

const allowedAdBoardCtaTypes = [
  "none",
  "merchant",
  "category",
  "product",
  "taxi",
  "url",
  "internal_campaign_page",
  "store_ad",
  "promo_code",
  "category_ad",
  "external_link",
  "internal_route",
];

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
  if (!isOptionalString(body?.targetRoute, 240)) errors.push("targetRoute");
  if (!isOptionalString(body?.promoCode, 120)) errors.push("promoCode");
  if (!isOptionalString(body?.category, 120)) errors.push("category");
  if (!isOptionalString(body?.externalLink, 1200)) errors.push("externalLink");

  const merchantId =
    body?.merchantId === undefined || body?.merchantId === null || body?.merchantId === ""
      ? null
      : Number(body.merchantId);
  if (merchantId !== null && (!Number.isInteger(merchantId) || merchantId <= 0)) {
    errors.push("merchantId");
  }
  const targetId =
    body?.targetId === undefined || body?.targetId === null || body?.targetId === ""
      ? null
      : Number(body.targetId);
  if (targetId !== null && (!Number.isInteger(targetId) || targetId <= 0)) {
    errors.push("targetId");
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

  const externalLink =
    body?.externalLink == null || String(body.externalLink).trim().isEmpty
      ? null
      : String(body.externalLink).trim();
  if (externalLink != null) {
    try {
      const parsed = new URL(externalLink);
      if (parsed.protocol !== "https:") errors.push("externalLink");
    } catch (_) {
      errors.push("externalLink");
    }
  }

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
          ? "store_ad"
          : "none",
      ctaTargetValue: body?.ctaTargetValue ? String(body.ctaTargetValue).trim() : null,
      merchantId,
      targetId,
      targetRoute: body?.targetRoute ? String(body.targetRoute).trim() : null,
      promoCode: body?.promoCode ? String(body.promoCode).trim() : null,
      category: body?.category ? String(body.category).trim() : null,
      externalLink,
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
  if (body?.targetRoute !== undefined) {
    if (!isOptionalString(body.targetRoute, 240)) errors.push("targetRoute");
    else value.targetRoute = body.targetRoute ? String(body.targetRoute).trim() : null;
  }
  if (body?.promoCode !== undefined) {
    if (!isOptionalString(body.promoCode, 120)) errors.push("promoCode");
    else value.promoCode = body.promoCode ? String(body.promoCode).trim() : null;
  }
  if (body?.category !== undefined) {
    if (!isOptionalString(body.category, 120)) errors.push("category");
    else value.category = body.category ? String(body.category).trim() : null;
  }
  if (body?.externalLink !== undefined) {
    if (!isOptionalString(body.externalLink, 1200)) {
      errors.push("externalLink");
    } else if (body.externalLink == null || String(body.externalLink).trim().isEmpty) {
      value.externalLink = null;
    } else {
      const normalized = String(body.externalLink).trim();
      try {
        const parsed = new URL(normalized);
        if (parsed.protocol !== "https:") {
          errors.push("externalLink");
        } else {
          value.externalLink = normalized;
        }
      } catch (_) {
        errors.push("externalLink");
      }
    }
  }
  if (body?.targetId !== undefined) {
    if (body.targetId === null || body.targetId === "") {
      value.targetId = null;
    } else {
      const targetId = Number(body.targetId);
      if (!Number.isInteger(targetId) || targetId <= 0) errors.push("targetId");
      else value.targetId = targetId;
    }
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

function parsePositiveInt(value, { fallback = null, min = 1, max = 10000 } = {}) {
  if (value === undefined || value === null || value === "") return fallback;
  const n = Number(value);
  if (!Number.isInteger(n)) return null;
  if (n < min) return null;
  if (n > max) return null;
  return n;
}
