import { AppError } from "../../shared/utils/errors.js";
import { createNotification } from "../notifications/notifications.repo.js";
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
 * ينشئ إعلان عقار جديداً وينشره مباشرة.
 */
export async function createListing(userId, dto, files) {
  return repo.createListing(userId, dto, files);
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
