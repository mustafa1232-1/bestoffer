import { pool } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import {
  createManyNotifications,
  createNotification,
} from "../notifications/notifications.repo.js";
import { syncVisibilityForOwner } from "../real-estate/real-estate.repo.js";
import * as repo from "./paid-upgrades.repo.js";

const PAID_UPGRADE_MAINTENANCE_INTERVAL_MS = 24 * 60 * 60 * 1000;
let maintenanceWorker = null;

function normalizePlanCode(value) {
  return String(value || "").trim().toLowerCase();
}

async function notifyBackoffice(payloadFactory) {
  const adminIds = await repo.listBackofficeUserIds();
  if (!adminIds.length) return;
  await createManyNotifications(
    adminIds.map((userId) => payloadFactory(Number(userId)))
  );
}

async function syncPropertySellerVisibility(userId) {
  const changedListingIds = await syncVisibilityForOwner(userId);
  if (!changedListingIds.length) return changedListingIds;
  await createNotification({
    userId: Number(userId),
    type: "real_estate.listing.hidden_due_subscription_expiry",
    title: "تم تعليق ظهور العقارات مؤقتًا",
    body: "انتهى اشتراك بائع العقارات، لذلك أُخفيت الإعلانات من العامة لحين التجديد.",
    payload: {
      target: "real_estate_workspace",
      targetModule: "customer",
      listingIds: changedListingIds,
      requiresAction: false,
    },
  });
  return changedListingIds;
}

export async function runPaidUpgradeMaintenanceTick() {
  const expired = await repo.expireDueSubscriptions();
  const propertySellerUserIds = [
    ...new Set(
      expired
        .filter((item) => item?.planCode === "property_seller_monthly")
        .concat(expired.filter((item) => item?.planCode === "premium_monthly"))
        .map((item) => Number(item.userId))
        .filter((value) => Number.isInteger(value) && value > 0)
    ),
  ];
  // Run all visibility syncs in parallel instead of sequentially
  await Promise.all(propertySellerUserIds.map((userId) => syncPropertySellerVisibility(userId)));
  return {
    expiredCount: expired.length,
    propertySellerUserIds,
  };
}

export function startPaidUpgradeMaintenanceWorker() {
  if (maintenanceWorker) return;
  const tick = async () => {
    try {
      await runPaidUpgradeMaintenanceTick();
    } catch (error) {
      console.warn(
        "[paid-upgrades] maintenance worker tick failed",
        error?.message || error
      );
    }
  };
  void tick();
  maintenanceWorker = setInterval(() => {
    void tick();
  }, PAID_UPGRADE_MAINTENANCE_INTERVAL_MS);
}

export function stopPaidUpgradeMaintenanceWorker() {
  if (maintenanceWorker) {
    clearInterval(maintenanceWorker);
    maintenanceWorker = null;
  }
}

export async function listPlans() {
  await repo.ensureDefaultPlans();
  return repo.listPlans();
}

export async function getMySummary(userId) {
  await repo.ensureDefaultPlans();
  await repo.expireDueSubscriptions();
  return repo.getMySummary(userId);
}

export async function listMyRequests(userId, query = {}) {
  return repo.listMyRequests(userId, query);
}

export async function listMySubscriptions(userId) {
  await repo.expireDueSubscriptions();
  return repo.listMySubscriptions(userId);
}

export async function createPaidUpgradeRequests(userId, dto) {
  await repo.ensureDefaultPlans();
  const planCodes = [...new Set(dto.planCodes.map(normalizePlanCode))];
  const plans = [];
  for (const code of planCodes) {
    const plan = await repo.getPlanByCode(code);
    if (!plan || !plan.isActive) {
      throw new AppError("INVALID_PLAN", 400, {
        fields: ["planCodes"],
        expose: true,
      });
    }
    plans.push(plan);
  }

  const client = await pool.connect();
  let created = [];
  try {
    await client.query("BEGIN");
    created = await repo.createRequestsTx(client, userId, plans, dto);
    await client.query("COMMIT");
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }

  if (created.length > 0) {
    await Promise.all([
      createManyNotifications(
        created.map((request) => ({
          userId: Number(userId),
          type: "paid_upgrade.request_submitted",
          title: "تم استلام طلب الترقية",
          body: `تم إرسال طلب ${request.planTitle || request.planCode || "ترقية"} للمراجعة.`,
          payload: {
            target: "paid_upgrades_home",
            targetModule: "customer",
            requestId: request.id,
            planCode: request.planCode,
            planTitle: request.planTitle,
            requiresAction: false,
          },
        }))
      ),
      notifyBackoffice((adminUserId) => ({
        userId: adminUserId,
        type: "paid_upgrade.request_submitted",
        title: "طلب ترقية جديد",
        body: `${dto.activityName || "طلب ترقية"} بانتظار المراجعة.`,
        payload: {
          target: "admin_paid_upgrade_requests",
          targetModule: "admin",
          requestIds: created.map((request) => request.id),
          planCodes,
          requiresAction: true,
        },
      })),
    ]);
  }

  return created;
}

export async function listMyPaidUpgradeRequests(userId, query = {}) {
  return repo.listMyRequests(userId, query);
}

export async function cancelMyPaidUpgradeRequest(userId, requestId) {
  const request = await repo.cancelRequest(userId, requestId);
  if (!request) {
    throw new AppError("PAID_UPGRADE_REQUEST_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: Number(userId),
    type: "paid_upgrade.request_cancelled",
    title: "تم إلغاء طلب الترقية",
    body: `تم إلغاء طلب ${request.planTitle || request.planCode || "الترقية"}.`,
    payload: {
      target: "paid_upgrades_home",
      targetModule: "customer",
      requestId: request.id,
      planCode: request.planCode,
      requiresAction: false,
    },
  });

  return request;
}

export async function listPendingPaidUpgradeRequests(query = {}) {
  await repo.ensureDefaultPlans();
  return repo.listPendingRequests(query);
}

export async function approvePaidUpgradeRequest(requestId, actor) {
  const result = await repo.adminActivateRequest(requestId, {
    actorUserId: actor.userId,
    reviewNote: actor.reviewNote || null,
    autoApprove: true,
  });
  if (!result) {
    throw new AppError("PAID_UPGRADE_REQUEST_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: result.request.userId,
    type: "paid_upgrade.activated",
    title: "تمت الموافقة وتفعيل الاشتراك",
    body: `${result.request.planTitle || result.request.planCode || "الاشتراك"} أصبح فعالًا حتى ${result.subscription?.expiresAt ? new Date(result.subscription.expiresAt).toISOString().split("T")[0] : "-"}.`,
    payload: {
      target: "paid_upgrades_home",
      targetModule: "customer",
      requestId: result.request.id,
      subscriptionId: result.subscription?.id || null,
      planCode: result.request.planCode,
      expiresAt: result.subscription?.expiresAt || null,
      requiresAction: false,
    },
  });

  if (
    result.request.planCode === "property_seller_monthly" ||
    result.request.planCode === "premium_monthly"
  ) {
    await syncVisibilityForOwner(result.request.userId);
  }

  return result.request;
}

export async function rejectPaidUpgradeRequest(requestId, actor) {
  const request = await repo.adminReviewRequest(requestId, {
    status: "rejected",
    reviewNote: actor.reviewNote || null,
    actorUserId: actor.userId,
  });
  if (!request) {
    throw new AppError("PAID_UPGRADE_REQUEST_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: request.userId,
    type: "paid_upgrade.rejected",
    title: "تم رفض طلب الترقية",
    body: `تم رفض ${request.planTitle || request.planCode || "طلب الترقية"}.`,
    payload: {
      target: "paid_upgrades_home",
      targetModule: "customer",
      requestId: request.id,
      planCode: request.planCode,
      requiresAction: false,
    },
  });

  return request;
}

export async function activatePaidUpgradeRequest(requestId, actor) {
  const result = await repo.adminActivateRequest(requestId, {
    actorUserId: actor.userId,
  });
  if (!result) {
    throw new AppError("PAID_UPGRADE_REQUEST_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: result.request.userId,
    type: "paid_upgrade.activated",
    title: "تم تفعيل الاشتراك",
    body: `${result.request.planTitle || result.request.planCode || "الترقية"} فعّلت لمدة 30 يومًا.`,
    payload: {
      target: "paid_upgrades_home",
      targetModule: "customer",
      requestId: result.request.id,
      subscriptionId: result.subscription.id,
      planCode: result.request.planCode,
      expiresAt: result.subscription.expiresAt,
      requiresAction: false,
    },
  });

  if (
    result.request.planCode === "property_seller_monthly" ||
    result.request.planCode === "premium_monthly"
  ) {
    await syncVisibilityForOwner(result.request.userId);
  }

  return result;
}

export async function getMyPaidUpgradeEntitlements(userId) {
  return repo.getMySummary(userId);
}
