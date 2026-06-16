function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function optionalText(value, max = 1200) {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim().length <= max)
  );
}

function requiredText(value, max = 180) {
  return typeof value === "string" && value.trim().length > 0 && value.trim().length <= max;
}

function parseLimit(value, fallback = 60) {
  const n = toInt(value);
  if (!n) return fallback;
  return Math.max(1, Math.min(500, n));
}

export function validateCouponUpsertBody(body = {}) {
  const errors = {};
  const tiers = Array.isArray(body.tiers) ? body.tiers : [];
  const code = String(body.code || "").trim().toUpperCase();
  const title = String(body.title || "").trim();
  const description = body.description == null ? null : String(body.description).trim();
  const validFrom = body.validFrom || null;
  const validUntil = body.validUntil || null;
  const maxUsesPerUser = Number(body.maxUsesPerUser || 1);
  const maxTotalUses =
    body.maxTotalUses == null || body.maxTotalUses === ""
      ? null
      : Number(body.maxTotalUses);
  const applyWholeApp = body.applyWholeApp === true;

  if (code && !/^[A-Z]{2}[0-9]{3}$/.test(code)) {
    errors.code = "INVALID_COUPON_CODE";
  }
  if (!requiredText(title, 140)) errors.title = "REQUIRED";
  if (!optionalText(description, 2000)) errors.description = "TOO_LONG";
  if (!Number.isInteger(maxUsesPerUser) || maxUsesPerUser < 1 || maxUsesPerUser > 3) {
    errors.maxUsesPerUser = "INVALID_NUMBER";
  }
  if (
    maxTotalUses != null &&
    (!Number.isInteger(maxTotalUses) || maxTotalUses < 1 || maxTotalUses > 1000000)
  ) {
    errors.maxTotalUses = "INVALID_NUMBER";
  }

  if (validFrom && Number.isNaN(new Date(validFrom).getTime())) {
    errors.validFrom = "INVALID_DATE";
  }
  if (validUntil && Number.isNaN(new Date(validUntil).getTime())) {
    errors.validUntil = "INVALID_DATE";
  }
  if (validFrom && validUntil && new Date(validUntil) <= new Date(validFrom)) {
    errors.dateRange = "INVALID_DATE_RANGE";
  }

  if (!Array.isArray(tiers) || tiers.length === 0) {
    errors.tiers = "REQUIRED";
  } else {
    const seenUseIndexes = new Set();
    for (const item of tiers) {
      const useIndex = Number(item?.useIndex);
      const discountValue = Number(item?.discountValue);
      const discountType = String(item?.discountType || "").trim().toLowerCase();
      if (!Number.isInteger(useIndex) || useIndex < 1 || useIndex > 3) {
        errors.tiers = "INVALID_TIER";
        break;
      }
      if (seenUseIndexes.has(useIndex)) {
        errors.tiers = "DUPLICATE_TIER";
        break;
      }
      seenUseIndexes.add(useIndex);
      if (!["percent", "amount"].includes(discountType)) {
        errors.tiers = "INVALID_TIER";
        break;
      }
      if (!Number.isFinite(discountValue) || discountValue <= 0) {
        errors.tiers = "INVALID_TIER";
        break;
      }
    }
  }

  const parseIdArray = (value) =>
    Array.isArray(value)
      ? [...new Set(value.map((x) => toInt(x)).filter((x) => x && x > 0))]
      : [];

  const parseCodeArray = (value) =>
    Array.isArray(value)
      ? [...new Set(value.map((x) => String(x || "").trim().toUpperCase()).filter(Boolean))]
      : [];

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      code,
      title,
      description,
      validFrom,
      validUntil,
      isActive: body.isActive !== false,
      maxUsesPerUser,
      maxTotalUses,
      applyWholeApp,
      tiers,
      targetUserIds: applyWholeApp ? [] : parseIdArray(body.targetUserIds),
      targetBuildings: applyWholeApp ? [] : parseCodeArray(body.targetBuildings),
      targetBlocks: applyWholeApp ? [] : parseCodeArray(body.targetBlocks),
      targetCompounds: applyWholeApp ? [] : parseCodeArray(body.targetCompounds),
    },
  };
}

export function validateLookupQuery(query = {}) {
  return {
    ok: true,
    errors: [],
    value: {
      query: String(query.query || "").trim(),
      limit: parseLimit(query.limit, 40),
    },
  };
}

export function validateCaptainGiftBody(body = {}) {
  const errors = {};
  const rewardValue = Number(body.rewardValue);
  const rewardType = String(body.rewardType || "credit").trim().toLowerCase();
  if (!Number.isFinite(rewardValue) || rewardValue <= 0) {
    errors.rewardValue = "INVALID_NUMBER";
  }
  if (!["credit", "cash_equivalent", "subscription_discount", "gift"].includes(rewardType)) {
    errors.rewardType = "INVALID_OPTION";
  }
  if (!optionalText(body.reason, 400)) errors.reason = "TOO_LONG";
  if (!optionalText(body.adminNote, 1200)) errors.adminNote = "TOO_LONG";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      rewardValue,
      rewardType,
      reason: body.reason == null ? null : String(body.reason).trim(),
      adminNote: body.adminNote == null ? null : String(body.adminNote).trim(),
    },
  };
}

export function validateCaptainWarningBody(body = {}) {
  const errors = {};
  const severity = String(body.severity || "medium").trim().toLowerCase();
  const statusEffect =
    body.statusEffect == null ? null : String(body.statusEffect).trim().toLowerCase();
  const affectsStatus = body.affectsStatus !== false;

  if (!["low", "medium", "high", "critical"].includes(severity)) {
    errors.severity = "INVALID_OPTION";
  }
  if (
    statusEffect != null &&
    !["warned", "temporarily_suspended", "under_review", "banned"].includes(statusEffect)
  ) {
    errors.statusEffect = "INVALID_OPTION";
  }
  if (!optionalText(body.reasonCode, 80)) errors.reasonCode = "TOO_LONG";
  if (!optionalText(body.reasonText, 1200)) errors.reasonText = "TOO_LONG";
  if (!optionalText(body.adminNote, 1200)) errors.adminNote = "TOO_LONG";
  if (body.expiresAt && Number.isNaN(new Date(body.expiresAt).getTime())) {
    errors.expiresAt = "INVALID_DATE";
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      severity,
      statusEffect,
      affectsStatus,
      reasonCode: body.reasonCode == null ? null : String(body.reasonCode).trim(),
      reasonText: body.reasonText == null ? null : String(body.reasonText).trim(),
      adminNote: body.adminNote == null ? null : String(body.adminNote).trim(),
      expiresAt: body.expiresAt || null,
    },
  };
}

export function validateCaptainStatusBody(body = {}) {
  const errors = {};
  const newStatus = String(body.newStatus || "").trim().toLowerCase();
  if (!["active", "warned", "temporarily_suspended", "under_review", "banned"].includes(newStatus)) {
    errors.newStatus = "INVALID_OPTION";
  }
  if (!optionalText(body.reasonCode, 80)) errors.reasonCode = "TOO_LONG";
  if (!optionalText(body.note, 1200)) errors.note = "TOO_LONG";
  if (body.suspendedUntil && Number.isNaN(new Date(body.suspendedUntil).getTime())) {
    errors.suspendedUntil = "INVALID_DATE";
  }
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      newStatus,
      reasonCode: body.reasonCode == null ? null : String(body.reasonCode).trim(),
      note: body.note == null ? null : String(body.note).trim(),
      suspendedUntil: body.suspendedUntil || null,
    },
  };
}

export function validateComplaintReviewBody(body = {}) {
  const errors = {};
  const status = String(body.status || "").trim().toLowerCase();
  if (!["under_review", "resolved", "rejected"].includes(status)) {
    errors.status = "INVALID_OPTION";
  }
  if (!optionalText(body.adminNote, 1200)) errors.adminNote = "TOO_LONG";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      status,
      adminNote: body.adminNote == null ? null : String(body.adminNote).trim(),
    },
  };
}

export function validateReportQuery(query = {}) {
  const type = String(query.type || "captains").trim().toLowerCase();
  const allowed = new Set([
    "captains",
    "coupons",
    "contests",
    "credits",
    "complaints",
    "captain_ratings",
    "rider_ratings",
    "warnings",
  ]);
  const safeType = allowed.has(type) ? type : "captains";
  return {
    ok: true,
    errors: [],
    value: {
      type: safeType,
      limit: parseLimit(query.limit, 200),
    },
  };
}

export function validateKpiQuery(query = {}) {
  const period = String(query.period || "month").trim().toLowerCase();
  return {
    ok: true,
    errors: [],
    value: {
      period: ["day", "week", "month"].includes(period) ? period : "month",
    },
  };
}

export function validateContestUpsertBody(body = {}) {
  const errors = {};
  const title = String(body.title || "").trim();
  const description = body.description == null ? null : String(body.description).trim();
  const startAt = body.startAt || body.start_at || null;
  const endAt = body.endAt || body.end_at || null;
  const targetType = String(body.targetType || body.target_type || "").trim().toLowerCase();
  const targetValue = Number(body.targetValue ?? body.target_value);
  const rewardType = String(body.rewardType || body.reward_type || "").trim().toLowerCase();
  const rewardValue = Number(body.rewardValue ?? body.reward_value);
  const isActive = body.isActive !== false;
  const eligibilityRules = body.eligibilityRules ?? body.eligibility_rules ?? null;
  const tiers = Array.isArray(body.tiers) ? body.tiers : [];

  if (!requiredText(title, 180)) errors.title = "REQUIRED";
  if (!optionalText(description, 5000)) errors.description = "TOO_LONG";
  if (!startAt || Number.isNaN(new Date(startAt).getTime())) errors.startAt = "INVALID_DATE";
  if (!endAt || Number.isNaN(new Date(endAt).getTime())) errors.endAt = "INVALID_DATE";
  if (startAt && endAt && !Number.isNaN(new Date(startAt).getTime()) && !Number.isNaN(new Date(endAt).getTime())) {
    if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
      errors.dateRange = "INVALID_DATE_RANGE";
    }
  }

  if (!["trips_count", "completed_rides", "rating_avg", "accepted_bids"].includes(targetType)) {
    errors.targetType = "INVALID_OPTION";
  }
  if (!Number.isFinite(targetValue) || targetValue <= 0) errors.targetValue = "INVALID_NUMBER";

  if (!["credit", "cash_equivalent", "subscription_discount", "gift"].includes(rewardType)) {
    errors.rewardType = "INVALID_OPTION";
  }
  if (!Number.isFinite(rewardValue) || rewardValue < 0) errors.rewardValue = "INVALID_NUMBER";

  const normalizedTiers = [];
  for (const tier of tiers) {
    const tierTargetValue = Number(tier?.targetValue ?? tier?.target_value);
    const tierRewardType = String(
      tier?.rewardType ?? tier?.reward_type ?? rewardType
    )
      .trim()
      .toLowerCase();
    const tierRewardValue = Number(tier?.rewardValue ?? tier?.reward_value);
    if (!Number.isFinite(tierTargetValue) || tierTargetValue <= 0) {
      errors.tiers = "INVALID_TIER";
      break;
    }
    if (!["credit", "cash_equivalent", "subscription_discount", "gift"].includes(tierRewardType)) {
      errors.tiers = "INVALID_TIER";
      break;
    }
    if (!Number.isFinite(tierRewardValue) || tierRewardValue < 0) {
      errors.tiers = "INVALID_TIER";
      break;
    }
    normalizedTiers.push({
      targetValue: tierTargetValue,
      rewardType: tierRewardType,
      rewardValue: tierRewardValue,
    });
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      title,
      description,
      startAt,
      endAt,
      targetType,
      targetValue,
      rewardType,
      rewardValue,
      isActive,
      eligibilityRules:
        eligibilityRules && typeof eligibilityRules === "object"
          ? eligibilityRules
          : null,
      tiers: normalizedTiers,
    },
  };
}
