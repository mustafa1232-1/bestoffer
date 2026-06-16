import { createNotification } from "../notifications/notifications.repo.js";
import { AppError } from "../../shared/utils/errors.js";
import * as loyaltyRepo from "./taxi.loyalty.repo.js";

function asId(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function ensureAdminActor(actor = {}) {
  const role = String(actor.userRole || actor.role || "").trim().toLowerCase();
  const isSuperAdmin =
    actor.userIsSuperAdmin === true ||
    actor.isSuperAdmin === true ||
    actor?.user?.is_super_admin === true ||
    actor?.user?.isSuperAdmin === true;
  const actorUserId = asId(actor.userId || actor.id);
  if (!actorUserId) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }
  if (role !== "admin" && !isSuperAdmin) {
    throw new AppError("FORBIDDEN_ADMIN_ONLY", { status: 403 });
  }
  return actorUserId;
}

async function notifyUser(userId, type, title, body, payload = null) {
  if (!asId(userId)) return;
  try {
    await createNotification({
      userId: Number(userId),
      type,
      title,
      body,
      payload: payload || {},
      orderId: null,
      merchantId: null,
    });
  } catch {
    // Notification failure must not break core flow.
  }
}

export async function listSavedPlaces(userId) {
  return loyaltyRepo.listSavedPlaces(userId);
}

export async function createSavedPlace(userId, dto) {
  return loyaltyRepo.createSavedPlace(userId, dto);
}

export async function updateSavedPlace(userId, placeId, patch) {
  const updated = await loyaltyRepo.updateSavedPlace(userId, placeId, patch);
  if (!updated) throw new AppError("TAXI_SAVED_PLACE_NOT_FOUND", { status: 404 });
  return updated;
}

export async function deleteSavedPlace(userId, placeId) {
  const deleted = await loyaltyRepo.deleteSavedPlace(userId, placeId);
  if (!deleted) throw new AppError("TAXI_SAVED_PLACE_NOT_FOUND", { status: 404 });
  return { ok: true };
}

export async function importSavedPlacesFromCustomerAddresses(userId) {
  const insertedCount = await loyaltyRepo.importSavedPlacesFromCustomerAddresses(userId);
  return { insertedCount };
}

export async function listFavoriteTrips(userId) {
  return loyaltyRepo.listFavoriteTrips(userId);
}

export async function createFavoriteTrip(userId, dto) {
  return loyaltyRepo.createFavoriteTrip(userId, dto);
}

export async function updateFavoriteTrip(userId, favoriteTripId, patch) {
  const updated = await loyaltyRepo.updateFavoriteTrip(userId, favoriteTripId, patch);
  if (!updated) throw new AppError("TAXI_FAVORITE_TRIP_NOT_FOUND", { status: 404 });
  return updated;
}

export async function deleteFavoriteTrip(userId, favoriteTripId) {
  const deleted = await loyaltyRepo.deleteFavoriteTrip(userId, favoriteTripId);
  if (!deleted) throw new AppError("TAXI_FAVORITE_TRIP_NOT_FOUND", { status: 404 });
  return { ok: true };
}

export async function listScheduledRides(userId, query) {
  return loyaltyRepo.listScheduledRides(userId, query);
}

export async function createScheduledRide(userId, dto) {
  return loyaltyRepo.createScheduledRide(userId, dto);
}

export async function cancelScheduledRide(userId, scheduledRideId) {
  const out = await loyaltyRepo.cancelScheduledRide(userId, scheduledRideId);
  if (out.code === "NOT_FOUND") {
    throw new AppError("TAXI_SCHEDULED_RIDE_NOT_FOUND", { status: 404 });
  }
  if (out.code === "ALREADY_CLOSED") {
    throw new AppError("TAXI_SCHEDULED_RIDE_ALREADY_CLOSED", {
      status: 409,
      details: { status: out.status },
    });
  }
  if (out.code === "CANCELLATION_WINDOW_CLOSED") {
    throw new AppError("TAXI_SCHEDULED_RIDE_CANCELLATION_WINDOW_CLOSED", {
      status: 409,
      details: { status: out.status },
    });
  }
  return out.item;
}

export async function takeScheduledRidesForDispatch({
  leadMinutes = 10,
  limit = 30,
}) {
  return loyaltyRepo.takeScheduledRidesReadyForDispatch({ leadMinutes, limit });
}

export async function markScheduledRideDispatched(payload) {
  return loyaltyRepo.markScheduledRideDispatched(payload);
}

export async function markScheduledRideDispatchFailed(scheduledRideId) {
  await loyaltyRepo.markScheduledRideDispatchFailed(scheduledRideId);
}

export async function syncScheduledRideStatusFromRide({
  rideRequestId,
  nextStatus,
}) {
  return loyaltyRepo.syncScheduledRideStatusFromRide({ rideRequestId, nextStatus });
}

export async function previewCouponForUser({
  userId,
  couponCode,
  proposedFareIqd,
}) {
  const preview = await loyaltyRepo.getCouponPreviewForUser({
    userId,
    couponCode,
    proposedFareIqd,
  });
  if (preview.code !== "OK") {
    throw new AppError(preview.code, { status: 409 });
  }
  return preview;
}

export async function listMyCoupons(userId) {
  return loyaltyRepo.listMyCoupons(userId);
}

export async function settleCouponForCompletedRide({
  rideId,
  captainUserId,
  actorUserId = null,
}) {
  const out = await loyaltyRepo.settleCouponForCompletedRide({
    rideId,
    captainUserId,
    actorUserId,
  });
  if (out.code !== "OK" && out.code !== "NO_COUPON" && out.code !== "ALREADY_SETTLED") {
    return out;
  }
  if (out.code === "OK" && out.usage) {
    await notifyUser(
      captainUserId,
      "taxi.coupon.settlement.approved",
      "تم احتساب خصم الكوبون لصالحك",
      `تم إضافة ${Number(out.usage.discountIqd || 0)} د.ع إلى رصيدك.`,
      {
        rideId: Number(rideId),
        discountIqd: Number(out.usage.discountIqd || 0),
      }
    );
  }
  return out;
}

export async function listCaptainLoyaltyDashboard(captainUserId, { limit = 80 } = {}) {
  const [summary, ledger, contests, rewards, governance] = await Promise.all([
    loyaltyRepo.getCaptainSubscriptionSummary(captainUserId),
    loyaltyRepo.listCaptainLedger(captainUserId, { limit }),
    loyaltyRepo.listCaptainContests(captainUserId),
    loyaltyRepo.listCaptainRewards(captainUserId, { limit }),
    loyaltyRepo.getCaptainGovernanceStatus(captainUserId),
  ]);

  return {
    summary,
    ledger,
    contests,
    rewards,
    governance: governance.profile || null,
    warnings: governance.warnings || [],
  };
}

export async function refreshCaptainContestProgress(captainUserId) {
  const rewards = await loyaltyRepo.updateCaptainContestProgressAndRewards({
    captainUserId,
    actorUserId: null,
  });
  return { rewards };
}

export async function rateRiderByCaptain({
  rideId,
  captainUserId,
  rating,
  category,
  note,
}) {
  const out = await loyaltyRepo.createRiderReviewByCaptain({
    rideId,
    captainUserId,
    rating,
    category,
    note,
  });
  if (out.code === "RIDE_NOT_FOUND") {
    throw new AppError("TAXI_RIDE_NOT_FOUND", { status: 404 });
  }
  if (out.code === "RIDE_NOT_COMPLETED") {
    throw new AppError("TAXI_RIDE_NOT_COMPLETED", { status: 409 });
  }
  if (out.code === "FORBIDDEN") {
    throw new AppError("TAXI_RIDE_NOT_ASSIGNED_TO_CAPTAIN", { status: 403 });
  }
  return out.item;
}

export async function getComplaintEligibility({ rideId, riderUserId }) {
  return loyaltyRepo.getRideComplaintEligibility({ rideId, riderUserId });
}

export async function createCaptainComplaint({
  riderUserId,
  tripId,
  category,
  reason,
  details,
  attachmentUrl,
}) {
  const out = await loyaltyRepo.createCaptainComplaint({
    riderUserId,
    tripId,
    category,
    reason,
    details,
    attachmentUrl,
  });
  if (out.code === "OK") {
    return out.item;
  }
  const statusByCode = {
    RIDE_NOT_FOUND: 404,
    RIDE_NOT_OWNED_BY_RIDER: 403,
    RIDE_NOT_COMPLETED: 409,
    CAPTAIN_NOT_FOUND: 409,
    COMPLAINT_WINDOW_EXPIRED: 409,
    COMPLAINT_ALREADY_OPEN: 409,
  };
  throw new AppError(out.code || "TAXI_COMPLAINT_CREATE_FAILED", {
    status: statusByCode[out.code] || 400,
  });
}

export async function listRiderComplaints(riderUserId, query = {}) {
  return loyaltyRepo.listRiderComplaints(riderUserId, query);
}

function generateCouponCode() {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const first = letters[Math.floor(Math.random() * letters.length)];
  const second = letters[Math.floor(Math.random() * letters.length)];
  const digits = String(Math.floor(Math.random() * 1000)).padStart(3, "0");
  return `${first}${second}${digits}`;
}

function isCouponCodeUniqueConflict(error) {
  const pgCode = String(error?.code || "").trim();
  if (pgCode !== "23505") return false;
  const constraint = String(error?.constraint || "").toLowerCase();
  const detail = String(error?.detail || "").toLowerCase();
  return constraint.includes("taxi_coupon_code_key") || detail.includes("(code)");
}

function normalizeCouponUpsertDto(dto = {}) {
  const tiersInput = Array.isArray(dto.tiers) ? dto.tiers : [];
  const tiers = tiersInput
    .map((item) => ({
      useIndex: Number(item.useIndex ?? item.use_index),
      discountType: String((item.discountType ?? item.discount_type) || "percent")
        .trim()
        .toLowerCase(),
      discountValue: Number(item.discountValue ?? item.discount_value),
    }))
    .filter(
      (item) =>
        Number.isInteger(item.useIndex) &&
        item.useIndex >= 1 &&
        item.useIndex <= 3 &&
        ["percent", "amount"].includes(item.discountType) &&
        Number.isFinite(item.discountValue) &&
        item.discountValue > 0
    )
    .sort((a, b) => a.useIndex - b.useIndex);

  if (!tiers.length) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { tiers: "REQUIRED" } },
    });
  }

  const maxTierUseIndex = tiers[tiers.length - 1].useIndex;
  const maxUsesPerUser = Math.max(1, Math.min(3, Number(dto.maxUsesPerUser) || maxTierUseIndex));

  const title = String(dto.title || "").trim();
  const codeInput = String(dto.code || "").trim().toUpperCase();
  if (codeInput && !/^[A-Z]{2}[0-9]{3}$/.test(codeInput)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { code: "INVALID_COUPON_CODE" } },
    });
  }
  const code = codeInput || generateCouponCode();
  if (!title) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { title: "REQUIRED" } },
    });
  }

  const applyWholeApp = dto.applyWholeApp === true;
  return {
    code,
    title,
    description: dto.description ? String(dto.description).trim() : null,
    isActive: dto.isActive !== false,
    validFrom: dto.validFrom || null,
    validUntil: dto.validUntil || null,
    maxTotalUses:
      dto.maxTotalUses == null || dto.maxTotalUses === ""
        ? null
        : Number(dto.maxTotalUses),
    maxUsesPerUser,
    applyWholeApp,
    tiers: tiers.filter((tier) => tier.useIndex <= maxUsesPerUser),
    targetUserIds: applyWholeApp ? [] : (dto.targetUserIds || dto.target_user_ids || []),
    targetBuildings: applyWholeApp ? [] : (dto.targetBuildings || dto.target_buildings || []),
    targetBlocks: applyWholeApp ? [] : (dto.targetBlocks || dto.target_blocks || []),
    targetCompounds: applyWholeApp ? [] : (dto.targetCompounds || dto.target_compounds || []),
  };
}

function normalizeContestUpsertDto(dto = {}) {
  const title = String(dto.title || "").trim();
  if (!title) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { title: "REQUIRED" } },
    });
  }

  const startAt = dto.startAt || dto.start_at || null;
  const endAt = dto.endAt || dto.end_at || null;
  if (!startAt || Number.isNaN(new Date(startAt).getTime())) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { startAt: "INVALID_DATE" } },
    });
  }
  if (!endAt || Number.isNaN(new Date(endAt).getTime())) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { endAt: "INVALID_DATE" } },
    });
  }
  if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { dateRange: "INVALID_DATE_RANGE" } },
    });
  }

  const targetType = String(dto.targetType || dto.target_type || "")
    .trim()
    .toLowerCase();
  if (!["trips_count", "completed_rides", "rating_avg", "accepted_bids"].includes(targetType)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { targetType: "INVALID_OPTION" } },
    });
  }
  const targetValue = Number(dto.targetValue ?? dto.target_value);
  if (!Number.isFinite(targetValue) || targetValue <= 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { targetValue: "INVALID_NUMBER" } },
    });
  }

  const rewardType = String(dto.rewardType || dto.reward_type || "")
    .trim()
    .toLowerCase();
  if (!["credit", "cash_equivalent", "subscription_discount", "gift"].includes(rewardType)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { rewardType: "INVALID_OPTION" } },
    });
  }

  const rewardValue = Number(dto.rewardValue ?? dto.reward_value);
  if (!Number.isFinite(rewardValue) || rewardValue < 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { rewardValue: "INVALID_NUMBER" } },
    });
  }

  const tiers = Array.isArray(dto.tiers)
    ? dto.tiers
        .map((tier) => ({
          targetValue: Number(tier?.targetValue ?? tier?.target_value),
          rewardType: String(
            tier?.rewardType ?? tier?.reward_type ?? rewardType
          )
            .trim()
            .toLowerCase(),
          rewardValue: Number(tier?.rewardValue ?? tier?.reward_value),
        }))
        .filter(
          (tier) =>
            Number.isFinite(tier.targetValue) &&
            tier.targetValue > 0 &&
            ["credit", "cash_equivalent", "subscription_discount", "gift"].includes(
              tier.rewardType
            ) &&
            Number.isFinite(tier.rewardValue) &&
            tier.rewardValue >= 0
        )
        .sort((a, b) => a.targetValue - b.targetValue)
    : [];

  return {
    title,
    description: dto.description ? String(dto.description).trim() : null,
    startAt: new Date(startAt).toISOString(),
    endAt: new Date(endAt).toISOString(),
    targetType,
    targetValue,
    rewardType,
    rewardValue,
    isActive: dto.isActive !== false,
    eligibilityRules:
      dto.eligibilityRules && typeof dto.eligibilityRules === "object"
        ? dto.eligibilityRules
        : null,
    tiers,
  };
}

export async function adminListCoupons(actor, query = {}) {
  ensureAdminActor(actor);
  return loyaltyRepo.listCouponsForAdmin({
    includeInactive: query.includeInactive !== "false",
  });
}

export async function adminCreateCoupon(actor, dto) {
  const actorUserId = ensureAdminActor(actor);
  const hasManualCode = String(dto?.code || "").trim().length > 0;
  const maxAttempts = hasManualCode ? 1 : 7;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const normalized = normalizeCouponUpsertDto(
      hasManualCode ? dto : { ...dto, code: "" }
    );
    try {
      return await loyaltyRepo.upsertCouponByAdmin({
        couponId: null,
        dto: normalized,
        actorUserId,
      });
    } catch (error) {
      if (!isCouponCodeUniqueConflict(error)) {
        throw error;
      }
      if (hasManualCode) {
        throw new AppError("VALIDATION_ERROR", {
          status: 400,
          details: { fields: { code: "DUPLICATE" } },
        });
      }
      if (attempt >= maxAttempts) {
        throw new AppError("TAXI_COUPON_CODE_GENERATION_FAILED", {
          status: 500,
          expose: false,
        });
      }
    }
  }

  throw new AppError("TAXI_COUPON_CODE_GENERATION_FAILED", {
    status: 500,
    expose: false,
  });
}

export async function adminUpdateCoupon(actor, couponId, dto) {
  const actorUserId = ensureAdminActor(actor);
  const normalized = normalizeCouponUpsertDto(dto);
  let out = null;
  try {
    out = await loyaltyRepo.upsertCouponByAdmin({
      couponId,
      dto: normalized,
      actorUserId,
    });
  } catch (error) {
    if (isCouponCodeUniqueConflict(error)) {
      throw new AppError("VALIDATION_ERROR", {
        status: 400,
        details: { fields: { code: "DUPLICATE" } },
      });
    }
    throw error;
  }
  if (!out) throw new AppError("TAXI_COUPON_NOT_FOUND", { status: 404 });
  return out;
}

export async function adminDeleteCoupon(actor, couponId) {
  ensureAdminActor(actor);
  const deleted = await loyaltyRepo.deleteCouponByAdmin(couponId);
  if (!deleted) throw new AppError("TAXI_COUPON_NOT_FOUND", { status: 404 });
  return { ok: true };
}

export async function adminCouponTargetLookups(actor, { query = "", limit = 40 } = {}) {
  ensureAdminActor(actor);
  const [users, buildings, blocks, compounds] = await Promise.all([
    loyaltyRepo.searchCouponTargetUsers({ query, limit }),
    loyaltyRepo.searchCouponTargetBuildings({ query, limit }),
    loyaltyRepo.searchCouponTargetBlocks({ query, limit }),
    loyaltyRepo.searchCouponTargetCompounds({ query, limit }),
  ]);
  return { users, buildings, blocks, compounds };
}

export async function adminListContests(actor, query = {}) {
  ensureAdminActor(actor);
  return loyaltyRepo.listContestsForAdmin({
    includeInactive: query.includeInactive !== "false",
  });
}

export async function adminCreateContest(actor, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const normalized = normalizeContestUpsertDto(dto);
  return loyaltyRepo.upsertContestByAdmin({
    contestId: null,
    dto: normalized,
    actorUserId,
  });
}

export async function adminUpdateContest(actor, contestId, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const normalized = normalizeContestUpsertDto(dto);
  const out = await loyaltyRepo.upsertContestByAdmin({
    contestId,
    dto: normalized,
    actorUserId,
  });
  if (!out) throw new AppError("TAXI_CONTEST_NOT_FOUND", { status: 404 });
  return out;
}

export async function adminDeleteContest(actor, contestId) {
  ensureAdminActor(actor);
  const deleted = await loyaltyRepo.deleteContestByAdmin(contestId);
  if (!deleted) throw new AppError("TAXI_CONTEST_NOT_FOUND", { status: 404 });
  return { ok: true };
}

export async function adminFinalizeContest(actor, contestId) {
  ensureAdminActor(actor);
  const out = await loyaltyRepo.finalizeContestByAdmin(contestId);
  if (!out) throw new AppError("TAXI_CONTEST_NOT_FOUND", { status: 404 });
  return out;
}

export async function adminCaptainDetails(actor, captainUserId) {
  ensureAdminActor(actor);
  const details = await loyaltyRepo.getCaptainAdminDetails(captainUserId);
  if (!details.profile) throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  return details;
}

export async function adminIssueCaptainGift(actor, captainUserId, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const rewardValue = Math.max(0, Number(dto.rewardValue || 0));
  if (!Number.isFinite(rewardValue) || rewardValue <= 0) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { rewardValue: "INVALID_NUMBER" } },
    });
  }
  const rewardType = String(dto.rewardType || "credit").trim().toLowerCase();
  if (!["credit", "cash_equivalent", "subscription_discount", "gift"].includes(rewardType)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { rewardType: "INVALID_OPTION" } },
    });
  }
  const reward = await loyaltyRepo.createCaptainGiftReward({
    captainUserId,
    rewardType,
    rewardValue,
    reason: dto.reason ? String(dto.reason).trim() : null,
    adminNote: dto.adminNote ? String(dto.adminNote).trim() : null,
    actorUserId,
  });
  await notifyUser(
    captainUserId,
    "taxi.captain.gift.received",
    "تمت إضافة هدية أو كردت إلى حسابك",
    "تم إضافة رصيد جديد من الإدارة إلى سجل الحوافز.",
    {
      rewardId: reward ? Number(reward.id) : null,
      rewardType,
      rewardValue,
    }
  );
  return reward;
}

export async function adminIssueCaptainWarning(actor, captainUserId, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const severity = String(dto.severity || "medium").trim().toLowerCase();
  const allowedSeverity = new Set(["low", "medium", "high", "critical"]);
  if (!allowedSeverity.has(severity)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { severity: "INVALID_OPTION" } },
    });
  }
  const statusEffectRaw = dto.statusEffect == null ? null : String(dto.statusEffect).trim().toLowerCase();
  if (
    statusEffectRaw != null &&
    !["warned", "temporarily_suspended", "under_review", "banned"].includes(statusEffectRaw)
  ) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { statusEffect: "INVALID_OPTION" } },
    });
  }

  const out = await loyaltyRepo.issueCaptainWarning({
    captainUserId,
    severity,
    reasonCode: dto.reasonCode ? String(dto.reasonCode).trim() : null,
    reasonText: dto.reasonText ? String(dto.reasonText).trim() : null,
    affectsStatus: dto.affectsStatus !== false,
    statusEffect: statusEffectRaw,
    adminNote: dto.adminNote ? String(dto.adminNote).trim() : null,
    issuedByUserId: actorUserId,
    expiresAt: dto.expiresAt || null,
  });

  if (out.code !== "OK") {
    if (out.code === "CAPTAIN_NOT_FOUND") {
      throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
    }
    throw new AppError("TAXI_CAPTAIN_WARNING_FAILED", { status: 400 });
  }

  await notifyUser(
    captainUserId,
    "taxi.captain.warning.issued",
    "تنبيه إداري على حساب الكابتن",
    "تم إصدار تنبيه إداري على حسابك. راجع الحالة في لوحة الكابتن.",
    {
      warningId: out.warning ? Number(out.warning.id) : null,
      nextStatus: out.nextStatus,
      severity,
    }
  );

  return out;
}

export async function adminSetCaptainStatus(actor, captainUserId, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const newStatus = String(dto.newStatus || "").trim().toLowerCase();
  if (!["active", "warned", "temporarily_suspended", "under_review", "banned"].includes(newStatus)) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { newStatus: "INVALID_OPTION" } },
    });
  }
  const out = await loyaltyRepo.setCaptainGovernanceStatus({
    captainUserId,
    newStatus,
    reasonCode: dto.reasonCode ? String(dto.reasonCode).trim() : null,
    note: dto.note ? String(dto.note).trim() : null,
    changedByUserId: actorUserId,
    suspendedUntil: dto.suspendedUntil || null,
  });
  if (out.code === "CAPTAIN_NOT_FOUND") {
    throw new AppError("TAXI_CAPTAIN_NOT_FOUND", { status: 404 });
  }
  await notifyUser(
    captainUserId,
    "taxi.captain.status.updated",
    "تم تحديث حالة حسابك",
    "تم تحديث حالة حسابك من قبل الإدارة.",
    {
      newStatus,
      reasonCode: dto.reasonCode || null,
    }
  );
  return out.profile;
}

export async function adminListComplaints(actor, query = {}) {
  ensureAdminActor(actor);
  return loyaltyRepo.listAdminComplaints(query);
}

export async function adminReviewComplaint(actor, complaintId, dto = {}) {
  const actorUserId = ensureAdminActor(actor);
  const out = await loyaltyRepo.reviewComplaintByAdmin({
    complaintId,
    nextStatus: dto.status,
    adminNote: dto.adminNote ? String(dto.adminNote).trim() : null,
    reviewerUserId: actorUserId,
  });
  if (!out) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: { status: "INVALID_OPTION" } },
    });
  }
  return out;
}

export async function adminTaxiKpiOverview(actor, query = {}) {
  ensureAdminActor(actor);
  return loyaltyRepo.getTaxiKpiOverview({
    period: String(query.period || "month").trim().toLowerCase(),
  });
}

export async function adminTaxiReports(actor, query = {}) {
  ensureAdminActor(actor);
  return loyaltyRepo.getTaxiReports({
    type: String(query.type || "captains").trim().toLowerCase(),
    limit: Number(query.limit || 200),
  });
}
