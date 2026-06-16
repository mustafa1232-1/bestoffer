import * as service from "./cars.service.js";
import { getCarsEntitlementSummary } from "./cars.entitlements.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import {
  validateBrowseCars,
  validateCarListingBody,
  validateCarListingQuery,
  validateMarkCarListingStatusBody,
  validateSmartSearch,
  validateUpdateCarListingBody,
} from "./cars.validators.js";

/**
 * Purpose:
 * controllers السيارات. تغطي browse/smart search وإدارة الإعلانات الخاصة
 * بالمستخدمين.
 */

/**
 * يحول الملفات المرفوعة إلى قائمة images صالحة للإدراج في listing.
 */
function parseFiles(req) {
  const files = Array.isArray(req.files) ? req.files : [];
  return files
    .map((file) => buildUploadedFileUrl(req, file))
    .filter((url) => typeof url === "string" && url.trim().length > 0)
    .map((imageUrl) => ({ imageUrl }));
}

/**
 * يعيد قائمة البراندات المدعومة من catalog.
 */
export async function listBrands(req, res, next) {
  try {
    const out = service.listBrands({
      search: req.query.search || "",
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listModels(req, res, next) {
  try {
    const out = service.listModels(req.query.brand || "", {
      search: req.query.search || "",
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

/**
 * يعيد نتيجة browse المبنية على الفلاتر فقط دون توصية ذكية.
 */
export async function browse(req, res, next) {
  try {
    const v = validateBrowseCars(req.query || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }

    const out = service.browseCars(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listListings(req, res, next) {
  try {
    const v = validateCarListingQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.listListings(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getListing(req, res, next) {
  try {
    const out = await service.getListing(req.params.listingId, req.userId || null);
    if (!out) {
      return res.status(404).json({ message: "CAR_LISTING_NOT_FOUND" });
    }
    res.json(out);
  } catch (error) {
    next(error);
  }
}

/**
 * يعيد توصيات smart search للسيارات.
 */
export async function smartSearch(req, res, next) {
  try {
    const v = validateSmartSearch(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }

    const out = service.smartSearch(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function entitlements(req, res, next) {
  try {
    const out = await getCarsEntitlementSummary(req.userId);
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
 * ينشئ إعلان سيارة جديداً للمستخدم الحالي.
 */
export async function createListing(req, res, next) {
  try {
    const v = validateCarListingBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.createListing(req.userId, v.value, parseFiles(req));
    res.status(201).json({ listing: out });
  } catch (error) {
    next(error);
  }
}

export async function updateListing(req, res, next) {
  try {
    const v = validateUpdateCarListingBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
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
    const v = validateMarkCarListingStatusBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.markStatus(req.userId, req.params.listingId, v.value);
    res.json({ listing: out });
  } catch (error) {
    next(error);
  }
}
