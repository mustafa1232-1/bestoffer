import * as service from "./merchants.service.js";
import { validateCreateMerchant } from "./merchants.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

const BROWSE_RESPONSE_HOT_TTL_MS = 15_000;
const browseResponseHotCache = new Map();
const PUBLIC_MERCHANT_HOT_TTL_MS = 15_000;
const publicMerchantHotCache = new Map();
const PUBLIC_MERCHANT_CACHE_CONTROL = "public, max-age=15, stale-while-revalidate=30";

export function browseResponseCacheKey(query = {}) {
  return JSON.stringify([
    String(query.type || "").trim().toLowerCase(),
    String(query.search || "").trim().toLowerCase(),
    String(query.activityType || query.activity_type || "")
      .trim()
      .toLowerCase(),
    String(query.discoverySubcategory || query.discovery_subcategory || "")
      .trim()
      .toLowerCase(),
    String(query.department || query.store_department || "")
      .trim()
      .toLowerCase(),
  ]);
}

function readHotBrowseResponse(query = {}) {
  const key = browseResponseCacheKey(query);
  const cached = browseResponseHotCache.get(key);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    browseResponseHotCache.delete(key);
    return null;
  }
  return cached.serialized;
}

function writeHotBrowseResponse(query = {}, payload) {
  const key = browseResponseCacheKey(query);
  browseResponseHotCache.set(key, {
    serialized: JSON.stringify(payload),
    expiresAt: Date.now() + BROWSE_RESPONSE_HOT_TTL_MS,
  });
}

function publicMerchantHotKey(prefix, parts = []) {
  return `${prefix}:${parts.map((value) => String(value ?? "")).join(":")}`;
}

function readPublicMerchantHot(prefix, parts = []) {
  const key = publicMerchantHotKey(prefix, parts);
  const cached = publicMerchantHotCache.get(key);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    publicMerchantHotCache.delete(key);
    return null;
  }
  return cached.serialized;
}

function writePublicMerchantHot(prefix, parts = [], payload) {
  const key = publicMerchantHotKey(prefix, parts);
  publicMerchantHotCache.set(key, {
    serialized: JSON.stringify(payload),
    expiresAt: Date.now() + PUBLIC_MERCHANT_HOT_TTL_MS,
  });
}

function parseOptionalBoolean(value) {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return value;
  const normalized = value.trim().toLowerCase();
  if (["true", "1", "yes", "on"].includes(normalized)) return true;
  if (["false", "0", "no", "off"].includes(normalized)) return false;
  return value;
}

function parseOptionalJson(value) {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value === "object") return value;
  if (typeof value !== "string") return undefined;
  try {
    return JSON.parse(value);
  } catch (_) {
    return undefined;
  }
}

function parseNumberOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Purpose:
 * controllers المتاجر العامة. تطبع body/files وتحوّل الطلبات إلى
 * `merchants.service.js` بعقود HTTP بسيطة.
 */

/**
 * ينشئ متجراً جديداً مع دعم owner موجود أو owner جديد من multipart fields.
 */
export async function create(req, res, next) {
  try {
    let parsedServiceFlags = req.body?.serviceFlags;
    if (typeof parsedServiceFlags === "string") {
      try {
        parsedServiceFlags = JSON.parse(parsedServiceFlags);
      } catch (_) {
        parsedServiceFlags = null;
      }
    }
    let parsedBadges = req.body?.badges;
    if (typeof parsedBadges === "string") {
      try {
        parsedBadges = JSON.parse(parsedBadges);
      } catch (_) {
        parsedBadges = null;
      }
    }
    const parsedDiscoverySubcategories = parseOptionalJson(
      req.body?.discoverySubcategories ?? req.body?.discovery_subcategories
    );

    const ownerFromFields =
      req.body?.ownerFullName ||
      req.body?.ownerPhone ||
      req.body?.ownerPin ||
      req.body?.ownerBlock ||
      req.body?.ownerBuildingNumber ||
      req.body?.ownerApartment ||
      req.body?.ownerImageUrl
        ? {
            fullName: req.body?.ownerFullName,
            phone: req.body?.ownerPhone,
            pin: req.body?.ownerPin,
            block: req.body?.ownerBlock,
            buildingNumber: req.body?.ownerBuildingNumber,
            apartment: req.body?.ownerApartment,
            imageUrl: req.body?.ownerImageUrl,
          }
        : null;

    const body = {
      ...req.body,
      activityType: req.body?.activityType || req.body?.activity_type,
      discoverySubcategory:
        req.body?.discoverySubcategory || req.body?.discovery_subcategory,
      discoverySubcategories: Array.isArray(parsedDiscoverySubcategories)
        ? parsedDiscoverySubcategories
        : req.body?.discoverySubcategories ?? req.body?.discovery_subcategories,
      discoverySelectAll: parseOptionalBoolean(
        req.body?.discoverySelectAll ?? req.body?.discovery_select_all
      ),
      serviceFlags: parsedServiceFlags,
      badges: parsedBadges,
      supportsChat: parseOptionalBoolean(req.body?.supportsChat),
      supportsAttachments: parseOptionalBoolean(req.body?.supportsAttachments),
      supportsPharmacyWorkflow: parseOptionalBoolean(
        req.body?.supportsPharmacyWorkflow
      ),
      imageUrl:
        buildUploadedFileUrl(req, req.files?.merchantImageFile?.[0]) ||
        req.body?.imageUrl,
      owner: req.body?.owner ?? ownerFromFields,
    };

    if (body.owner && typeof body.owner === "string") {
      try {
        body.owner = JSON.parse(body.owner);
      } catch (_) {
        body.owner = null;
      }
    }

    if (body.owner && typeof body.owner === "object") {
      body.owner = {
        ...body.owner,
        imageUrl:
          buildUploadedFileUrl(req, req.files?.ownerImageFile?.[0]) ||
          body.owner.imageUrl,
      };
    }

    const v = validateCreateMerchant(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const merchant = await service.createMerchant(body, req.userId);
    res.status(201).json(merchant);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد قائمة المتاجر العامة.
 */
export async function list(req, res, next) {
  try {
    res.set("Cache-Control", PUBLIC_MERCHANT_CACHE_CONTROL);
    const hot = readHotBrowseResponse(req.query);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const data = await service.listMerchants(req.query.type, req.query.search, {
      activityType: req.query.activityType ?? req.query.activity_type,
      discoverySubcategory:
        req.query.discoverySubcategory ?? req.query.discovery_subcategory,
      department: req.query.department ?? req.query.store_department,
    });
    writeHotBrowseResponse(req.query, data);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function discovery(req, res, next) {
  try {
    const data = await service.getCustomerDiscovery(req.userId, req.query.type, {
      activityType: req.query.activityType ?? req.query.activity_type,
      discoverySubcategory:
        req.query.discoverySubcategory ?? req.query.discovery_subcategory,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listActivities(req, res, next) {
  try {
    const data = await service.listStoreActivities();
    res.json({ items: data });
  } catch (e) {
    next(e);
  }
}

export async function listActivityDiscoveryOptions(req, res, next) {
  try {
    const activityType = req.query.activityType ?? req.query.activity_type;
    const data = await service.listStoreDiscoveryOptions(activityType);
    res.json({ items: data });
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد لوحة الإعلانات العامة للمتاجر.
 */
export async function adBoard(req, res, next) {
  try {
    const data = await service.listPublicAdBoard(req.query.type);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function nearby(req, res, next) {
  try {
    const data = await service.listNearbyMerchants({
      latitude: parseNumberOrNull(req.query.lat ?? req.query.latitude),
      longitude: parseNumberOrNull(req.query.lng ?? req.query.longitude ?? req.query.lon),
      radiusKm: parseNumberOrNull(req.query.radiusKm ?? req.query.radius_km),
      limit: parseNumberOrNull(req.query.limit),
      type: req.query.type,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function getById(req, res, next) {
  try {
    res.set("Cache-Control", PUBLIC_MERCHANT_CACHE_CONTROL);
    const merchantId = Number(req.params.merchantId);
    const hot = readPublicMerchantHot("merchant_summary", [merchantId]);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const data = await service.getPublicMerchantSummary(merchantId);
    writePublicMerchantHot("merchant_summary", [merchantId], data);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد منتجات متجر عام واحد.
 */
export async function listProducts(req, res, next) {
  try {
    const limit = Math.max(1, Math.min(200, Number(req.query?.limit) || 200));
    const offset = Math.max(0, Number(req.query?.offset) || 0);
    const merchantId = Number(req.params.merchantId);
    res.set("Cache-Control", PUBLIC_MERCHANT_CACHE_CONTROL);
    const hot = readPublicMerchantHot("merchant_products", [merchantId, limit, offset]);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const data = await service.listMerchantProducts(merchantId, { limit, offset });
    writePublicMerchantHot("merchant_products", [merchantId, limit, offset], data);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listCategories(req, res, next) {
  try {
    const merchantId = Number(req.params.merchantId);
    res.set("Cache-Control", PUBLIC_MERCHANT_CACHE_CONTROL);
    const hot = readPublicMerchantHot("merchant_categories", [merchantId]);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const data = await service.listMerchantCategories(merchantId);
    writePublicMerchantHot("merchant_categories", [merchantId], data);
    res.json(data);
  } catch (e) {
    next(e);
  }
}
