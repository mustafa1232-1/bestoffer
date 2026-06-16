import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import * as service from "./real-estate.service.js";
import {
  validateAdminReviewBody,
  validateCreateListingBody,
  validateListListingsQuery,
  validateMarkListingStatusBody,
  validateUpdateListingBody,
} from "./real-estate.validators.js";

/**
 * Purpose:
 * controllers العقارات. تضبط validation/رفع الصور وتحوّل المسارات إلى
 * `real-estate.service.js`.
 */

/**
 * يحول الملفات المرفوعة إلى قائمة صور صالحة للإعلان.
 */
function parseFiles(req) {
  const files = Array.isArray(req.files) ? req.files : [];
  return files
    .map((file) => buildUploadedFileUrl(req, file))
    .filter((url) => typeof url === "string" && url.trim().length > 0)
    .map((imageUrl) => ({ imageUrl }));
}

/**
 * يعيد الإعلانات العامة للعقارات بحسب الفلاتر.
 */
export async function listListings(req, res, next) {
  try {
    const v = validateListListingsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listListings(v.value, req.userId || null);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

/**
 * يعيد إعلان عقار واحداً أو 404 إذا لم يعد مرئياً.
 */
export async function getListing(req, res, next) {
  try {
    const out = await service.getListing(req.params.listingId, req.userId || null);
    if (!out) {
      return res.status(404).json({ message: "REAL_ESTATE_LISTING_NOT_FOUND" });
    }
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listSimilarListings(req, res, next) {
  try {
    const limit = Number(req.query?.limit || 6);
    const out = await service.listSimilarListings(
      req.params.listingId,
      req.userId || null,
      limit
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listSavedListings(req, res, next) {
  try {
    const out = await service.listSavedListings(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function saveListing(req, res, next) {
  try {
    const out = await service.saveListing(req.userId, req.params.listingId);
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function unsaveListing(req, res, next) {
  try {
    const out = await service.unsaveListing(req.userId, req.params.listingId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getWorkspace(req, res, next) {
  try {
    const out = await service.getWorkspace(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

/**
 * ينشئ إعلان عقار جديداً للمستخدم الحالي.
 */
export async function createListing(req, res, next) {
  try {
    const v = validateCreateListingBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.createListing(req.userId, v.value, parseFiles(req));
    res.status(201).json({ listing: out });
  } catch (error) {
    next(error);
  }
}

export async function updateListing(req, res, next) {
  try {
    const v = validateUpdateListingBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.updateListing(
      req.userId,
      req.params.listingId,
      v.value,
      parseFiles(req)
    );
    res.json({ listing: out });
  } catch (error) {
    next(error);
  }
}

export async function markStatus(req, res, next) {
  try {
    const v = validateMarkListingStatusBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.markStatus(req.userId, req.params.listingId, v.value);
    res.json({ listing: out });
  } catch (error) {
    next(error);
  }
}

/**
 * يعيد الإعلانات المنتظرة للمراجعة الإدارية.
 */
export async function listPendingListings(req, res, next) {
  try {
    const out = await service.listPendingListings(req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

/**
 * يوافق على إعلان عقار من جهة الأدمن.
 */
export async function approveListing(req, res, next) {
  try {
    const v = validateAdminReviewBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.approveListing(
      req.params.listingId,
      {
        userId: req.userId,
      },
      v.value.reviewNote
    );
    res.json({ listing: out });
  } catch (error) {
    next(error);
  }
}

export async function rejectListing(req, res, next) {
  try {
    const v = validateAdminReviewBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.rejectListing(
      req.params.listingId,
      {
        userId: req.userId,
      },
      v.value.reviewNote
    );
    res.json({ listing: out });
  } catch (error) {
    next(error);
  }
}
