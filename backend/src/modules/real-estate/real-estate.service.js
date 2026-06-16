import { AppError } from "../../shared/utils/errors.js";
import {
  createManyNotifications,
  createNotification,
} from "../notifications/notifications.repo.js";
import { listBackofficeUserIds } from "../paid-upgrades/paid-upgrades.repo.js";
import * as repo from "./real-estate.repo.js";

/**
 * Purpose:
 * منطق العقارات العام: التصفح، الحفظ، workspace، إنشاء الإعلانات،
 * والمراجعة الإدارية ونشر الإشعارات المتعلقة بها.
 *
 * Used by:
 * - `real-estate.controller.js`
 * - شاشات marketplace/workspace/admin review في Flutter
 */

async function notifyBackoffice(payloadFactory) {
  const adminIds = await listBackofficeUserIds();
  if (!adminIds.length) return;
  await createManyNotifications(
    adminIds.map((userId) => payloadFactory(Number(userId)))
  );
}

/**
 * يعيد الإعلانات العامة المرئية للمستخدم الحالي.
 */
export async function listListings(query, viewerUserId = null) {
  return repo.listPublicListings(query, { viewerUserId });
}

/**
 * يعيد إعلان عقار واحداً مع سياق الحفظ/المشاهدة إن توفر.
 */
export async function getListing(listingId, viewerUserId = null) {
  return repo.getListingById(listingId, { viewerUserId });
}

export async function listSimilarListings(listingId, viewerUserId = null, limit = 6) {
  return repo.listSimilarListings(listingId, { viewerUserId, limit });
}

export async function listSavedListings(userId, query = {}) {
  return repo.listSavedListings(userId, query);
}

export async function saveListing(userId, listingId) {
  const out = await repo.saveListing(userId, listingId);
  if (!out) {
    throw new AppError("REAL_ESTATE_LISTING_NOT_FOUND", 404, {
      expose: true,
    });
  }
  return out;
}

export async function unsaveListing(userId, listingId) {
  return repo.unsaveListing(userId, listingId);
}

export async function getWorkspace(userId) {
  return repo.getWorkspace(userId);
}

/**
 * ينشئ إعلان عقار جديداً ويرسل fan-out إشعار إلى المالك والـ backoffice.
 */
export async function createListing(userId, dto, files) {
  const listing = await repo.createListing(userId, dto, files);
  await Promise.all([
    createNotification({
      userId: Number(userId),
      type: "real_estate.listing.pending_admin_review",
      title: "تم استلام إعلان العقار",
      body: "إعلانك بانتظار مراجعة الأدمن قبل النشر.",
      payload: {
        target: "real_estate_workspace",
        targetModule: "customer",
        listingId: listing.id,
        requiresAction: false,
      },
    }),
    notifyBackoffice((adminUserId) => ({
      userId: adminUserId,
      type: "real_estate.listing.pending_admin_review",
      title: "إعلان عقار جديد",
      body: `${listing.title} بانتظار المراجعة.`,
      payload: {
        target: "admin_real_estate_pending",
        targetModule: "admin",
        listingId: listing.id,
        requiresAction: true,
      },
    })),
  ]);
  return listing;
}

export async function updateListing(userId, listingId, dto, files) {
  const listing = await repo.updateListing(userId, listingId, dto, files);
  if (!listing) {
    throw new AppError("REAL_ESTATE_LISTING_NOT_FOUND", 404, {
      expose: true,
    });
  }
  return listing;
}

export async function markStatus(userId, listingId, dto) {
  const listing = await repo.markListingStatus(
    userId,
    listingId,
    dto.nextStatus,
    dto.note
  );
  if (!listing) {
    throw new AppError("REAL_ESTATE_LISTING_NOT_FOUND", 404, {
      expose: true,
    });
  }
  return listing;
}

/**
 * يعيد قائمة الإعلانات المنتظرة للمراجعة الإدارية.
 */
export async function listPendingListings(query = {}) {
  return repo.listPendingListings(query);
}

/**
 * يوافق على إعلان عقار ويخطر المالك بالنتيجة.
 */
export async function approveListing(listingId, actor, note = null) {
  const listing = await repo.adminReviewListing(listingId, {
    status: "approved",
    note,
    actorUserId: actor.userId,
  });
  if (!listing) {
    throw new AppError("REAL_ESTATE_LISTING_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: listing.ownerId,
    type: "real_estate.listing.approved",
    title: "تمت الموافقة على إعلان العقار",
    body: `${listing.title} أصبح جاهزًا للنشر.`,
    payload: {
      target: "real_estate_workspace",
      targetModule: "customer",
      listingId: listing.id,
      requiresAction: false,
    },
  });

  return listing;
}

/**
 * يرفض إعلان عقار ويخطر المالك بالنتيجة.
 */
export async function rejectListing(listingId, actor, note = null) {
  const listing = await repo.adminReviewListing(listingId, {
    status: "rejected",
    note,
    actorUserId: actor.userId,
  });
  if (!listing) {
    throw new AppError("REAL_ESTATE_LISTING_NOT_FOUND", 404, {
      expose: true,
    });
  }

  await createNotification({
    userId: listing.ownerId,
    type: "real_estate.listing.rejected",
    title: "تم رفض إعلان العقار",
    body: `${listing.title} لم يتم قبوله.`,
    payload: {
      target: "real_estate_workspace",
      targetModule: "customer",
      listingId: listing.id,
      requiresAction: false,
    },
  });

  return listing;
}
