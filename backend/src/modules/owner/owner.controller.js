import * as service from "./owner.service.js";
import {
  validateOwnerAccountantCreate,
  validateOwnerAssignDelivery,
  validateOwnerAssignExistingStaff,
  validateOwnerCategoryCreate,
  validateOwnerCategoryUpdate,
  validateOwnerDeliveryAgentCreate,
  validateOwnerHrCreate,
  validateOwnerMerchantUpdate,
  validateOwnerOrderStatusUpdate,
  validateOwnerOfferCreate,
  validateOwnerOfferUpdate,
  validateOwnerProductCreate,
  validateOwnerProductUpdate,
  validateOwnerMarkOrderItemUnavailable,
  validateOwnerRegister,
  validateOwnerStaffSearchQuery,
  normalizeStockQuantityInput,
} from "./owner.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import { extractDeviceContext } from "../../shared/utils/device-fingerprint.js";

/**
 * Purpose: طبقة controller الخاصة بصاحب المتجر، وتغطي التسجيل، المتجر، الكاتالوج، الفريق، والطلبات.
 * Used by: `owner.routes.js` وكل واجهات owner في Flutter.
 * Depends on: validators الخاصة بالـ owner، `owner.service.js`، وhelpers رفع الملفات وبصمة الجهاز.
 * Critical notes: كثير من المسارات هنا تستقبل multipart/forms؛ لذلك بناء body وحقول الصور جزء أساسي من التشخيص.
 * Maintenance notes: إذا وصل `VALIDATION_ERROR` غير متوقع ابدأ من validator المرتبط بهذا handler ثم راجع coercion هنا قبل service.
 */

/**
 * يحول قيم boolean القادمة من form-data النصي إلى boolean فعلي أو `undefined`.
 *
 * يستخدم هذا helper لتجنب إرسال `"true"`/`"false"` إلى services والـ repo.
 */
function parseBooleanInput(value) {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return undefined;
  const lowered = value.trim().toLowerCase();
  if (lowered === "true") return true;
  if (lowered === "false") return false;
  return undefined;
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

function resolveProductUploadPayload(req, media = [], variantGroups = [], variants = []) {
  const galleryUrls = (req.files?.galleryFiles || [])
    .map((file) => buildUploadedFileUrl(req, file))
    .filter(Boolean);
  const variantUrls = (req.files?.variantFiles || [])
    .map((file) => buildUploadedFileUrl(req, file))
    .filter(Boolean);
  const resolvedMedia = (media || []).map((entry) => {
    const index = Number(entry?.uploadIndex);
    return Number.isInteger(index) && galleryUrls[index]
      ? { ...entry, imageUrl: galleryUrls[index] }
      : entry;
  });
  const usedGallery = new Set(
    resolvedMedia.map((entry) => entry?.imageUrl).filter(Boolean)
  );
  galleryUrls.forEach((imageUrl, index) => {
    if (!usedGallery.has(imageUrl)) {
      resolvedMedia.push({ imageUrl, isPrimary: false, sortOrder: resolvedMedia.length, uploadIndex: index });
    }
  });
  const resolvedVariantGroups = (variantGroups || []).map((group) => {
    const options = Array.isArray(group?.options)
      ? group.options.map((option) => {
          const index = Number(option?.uploadIndex);
          return Number.isInteger(index) && variantUrls[index]
            ? { ...option, imageUrl: variantUrls[index] }
            : option;
        })
      : group?.options;
    return Array.isArray(options) ? { ...group, options } : group;
  });
  const resolvedVariants = (variants || []).map((entry) => {
    const index = Number(entry?.uploadIndex);
    return Number.isInteger(index) && variantUrls[index]
      ? { ...entry, imageUrl: variantUrls[index] }
      : entry;
  });
  return { media: resolvedMedia, variantGroups: resolvedVariantGroups, variants: resolvedVariants };
}

/**
 * ينشئ حساب owner جديداً مع المتجر المرتبط به في خطوة واحدة.
 *
 * Side effects:
 * - يقرأ ملفات الصور المرفوعة.
 * - يمرر device context إلى service لإنشاء session قابلة للتتبع.
 */
export async function register(req, res, next) {
  try {
    const serviceFlags = parseOptionalJson(req.body?.merchantServiceFlags);
    const badges = parseOptionalJson(req.body?.merchantBadges);
    const discoverySubcategoriesRaw = parseOptionalJson(
      req.body?.merchantDiscoverySubcategories ??
        req.body?.merchant_discovery_subcategories
    );
    const body = {
      ...req.body,
      merchantActivityType:
        req.body?.merchantActivityType ?? req.body?.merchant_activity_type,
      merchantDiscoverySubcategory:
        req.body?.merchantDiscoverySubcategory ??
        req.body?.merchant_discovery_subcategory,
      merchantDiscoverySubcategories: Array.isArray(discoverySubcategoriesRaw)
        ? discoverySubcategoriesRaw
        : req.body?.merchantDiscoverySubcategories ??
            req.body?.merchant_discovery_subcategories,
      merchantDiscoverySelectAll: parseBooleanInput(
        req.body?.merchantDiscoverySelectAll ??
          req.body?.merchant_discovery_select_all
      ),
      merchantServiceFlags:
        serviceFlags && typeof serviceFlags === "object" && !Array.isArray(serviceFlags)
          ? serviceFlags
          : req.body?.merchantServiceFlags,
      merchantBadges: Array.isArray(badges) ? badges : req.body?.merchantBadges,
      merchantSupportsChat: parseBooleanInput(req.body?.merchantSupportsChat),
      merchantSupportsAttachments: parseBooleanInput(
        req.body?.merchantSupportsAttachments
      ),
      merchantSupportsPharmacyWorkflow: parseBooleanInput(
        req.body?.merchantSupportsPharmacyWorkflow
      ),
      ownerImageUrl:
        buildUploadedFileUrl(req, req.files?.ownerImageFile?.[0]) ||
        req.body?.ownerImageUrl,
      merchantImageUrl:
        buildUploadedFileUrl(req, req.files?.merchantImageFile?.[0]) ||
        req.body?.merchantImageUrl,
    };

    const v = validateOwnerRegister(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.registerOwner(body, extractDeviceContext(req));
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد بطاقة المتجر المرتبط بالمستخدم المصادق.
 */
export async function getMerchant(req, res, next) {
  try {
    const merchant = await service.getOwnerMerchant(req.userId);
    res.json({ merchant });
  } catch (e) {
    next(e);
  }
}

/**
 * يسجل قبول صاحب المتجر للشروط المالية بعد موافقة الإدارة.
 */
export async function acceptFinancialTerms(req, res, next) {
  try {
    const out = await service.acceptOwnerFinancialTerms(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يسجل رفض الشروط المالية مع ملاحظة اختيارية ليعود الملف إلى مراجعة الإدارة.
 */
export async function rejectFinancialTerms(req, res, next) {
  try {
    const note =
      typeof req.body?.note === "string" && req.body.note.trim().length
        ? req.body.note.trim()
        : null;
    const out = await service.rejectOwnerFinancialTerms(req.userId, note);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يحدّث بيانات المتجر وصورته وحالة الفتح/الإغلاق بعد تطبيع multipart body.
 */
export async function updateMerchant(req, res, next) {
  try {
    const discoverySubcategoriesRaw = parseOptionalJson(
      req.body?.discoverySubcategories ?? req.body?.discovery_subcategories
    );
    const body = {
      ...req.body,
      discoverySubcategories: Array.isArray(discoverySubcategoriesRaw)
        ? discoverySubcategoriesRaw
        : req.body?.discoverySubcategories ??
            req.body?.discovery_subcategories,
      discoverySelectAll: parseBooleanInput(
        req.body?.discoverySelectAll ?? req.body?.discovery_select_all
      ),
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
      isOpen:
        req.body?.isOpen === undefined
          ? undefined
          : parseBooleanInput(req.body?.isOpen),
    };

    const v = validateOwnerMerchantUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const merchant = await service.updateOwnerMerchant(req.userId, body);
    res.json({ merchant });
  } catch (e) {
    next(e);
  }
}

export async function listProducts(req, res, next) {
  try {
    const data = await service.listOwnerProducts(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listOffers(req, res, next) {
  try {
    const data = await service.listOwnerOffers(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listCategories(req, res, next) {
  try {
    const data = await service.listOwnerCategories(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function createCategory(req, res, next) {
  try {
    const v = validateOwnerCategoryCreate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const category = await service.createOwnerCategory(req.userId, req.body);
    res.status(201).json(category);
  } catch (e) {
    next(e);
  }
}

export async function updateCategory(req, res, next) {
  try {
    const v = validateOwnerCategoryUpdate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const category = await service.updateOwnerCategory(
      req.userId,
      Number(req.params.categoryId),
      req.body
    );
    res.json(category);
  } catch (e) {
    next(e);
  }
}

export async function deleteCategory(req, res, next) {
  try {
    await service.deleteOwnerCategory(req.userId, Number(req.params.categoryId));
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * ينشئ منتجاً جديداً لصاحب المتجر بعد دمج حقول form-data مع الملف المرفوع.
 */
export async function createProduct(req, res, next) {
  try {
    const richCatalog = parseOptionalJson(req.body?.richCatalog);
    const attributes = parseOptionalJson(req.body?.attributes);
    const variantGroups = parseOptionalJson(req.body?.variantGroups);
    const variants = parseOptionalJson(req.body?.variants);
    const media = parseOptionalJson(req.body?.media);
    const metadataJson = parseOptionalJson(
      req.body?.metadataJson ?? req.body?.metadata_json
    );
    const uploads = resolveProductUploadPayload(req, media, variantGroups, variants);
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.files?.imageFile?.[0]) || req.body?.imageUrl,
      freeDelivery:
        req.body?.freeDelivery === undefined
          ? undefined
          : parseBooleanInput(req.body?.freeDelivery),
      isAvailable:
        req.body?.isAvailable === undefined
          ? undefined
          : parseBooleanInput(req.body?.isAvailable),
      requiresPrescription:
        req.body?.requiresPrescription === undefined
          ? undefined
          : parseBooleanInput(req.body?.requiresPrescription),
      requiresReview:
        req.body?.requiresReview === undefined
          ? undefined
          : parseBooleanInput(req.body?.requiresReview),
      richCatalog:
        richCatalog && typeof richCatalog === "object" ? richCatalog : undefined,
      attributes: Array.isArray(attributes) ? attributes : undefined,
      variantGroups: Array.isArray(variantGroups) ? uploads.variantGroups : undefined,
      variants: Array.isArray(variants) ? uploads.variants : undefined,
      stockQuantity: normalizeStockQuantityInput(req.body?.stockQuantity),
      media: Array.isArray(media) || uploads.media.length ? uploads.media : undefined,
      metadataJson:
        metadataJson && typeof metadataJson === "object" ? metadataJson : undefined,
    };

    const v = validateOwnerProductCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const product = await service.createOwnerProduct(req.userId, body);
    res.status(201).json(product);
  } catch (e) {
    next(e);
  }
}

export async function createOffer(req, res, next) {
  try {
    const v = validateOwnerOfferCreate(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const offer = await service.createOwnerOffer(req.userId, req.body || {});
    res.status(201).json({ offer });
  } catch (e) {
    next(e);
  }
}

export async function updateProduct(req, res, next) {
  try {
    const richCatalog = parseOptionalJson(req.body?.richCatalog);
    const attributes = parseOptionalJson(req.body?.attributes);
    const variantGroups = parseOptionalJson(req.body?.variantGroups);
    const variants = parseOptionalJson(req.body?.variants);
    const media = parseOptionalJson(req.body?.media);
    const metadataJson = parseOptionalJson(
      req.body?.metadataJson ?? req.body?.metadata_json
    );
    const uploads = resolveProductUploadPayload(req, media, variantGroups, variants);
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.files?.imageFile?.[0]) || req.body?.imageUrl,
      freeDelivery:
        req.body?.freeDelivery === undefined
          ? undefined
          : parseBooleanInput(req.body?.freeDelivery),
      isAvailable:
        req.body?.isAvailable === undefined
          ? undefined
          : parseBooleanInput(req.body?.isAvailable),
      requiresPrescription:
        req.body?.requiresPrescription === undefined
          ? undefined
          : parseBooleanInput(req.body?.requiresPrescription),
      requiresReview:
        req.body?.requiresReview === undefined
          ? undefined
          : parseBooleanInput(req.body?.requiresReview),
      richCatalog:
        richCatalog && typeof richCatalog === "object" ? richCatalog : undefined,
      attributes: Array.isArray(attributes) ? attributes : undefined,
      variantGroups: Array.isArray(variantGroups) ? uploads.variantGroups : undefined,
      variants: Array.isArray(variants) ? uploads.variants : undefined,
      stockQuantity: normalizeStockQuantityInput(req.body?.stockQuantity),
      media: Array.isArray(media) || uploads.media.length ? uploads.media : undefined,
      metadataJson:
        metadataJson && typeof metadataJson === "object" ? metadataJson : undefined,
    };

    const v = validateOwnerProductUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const product = await service.updateOwnerProduct(
      req.userId,
      Number(req.params.productId),
      body
    );
    res.json(product);
  } catch (e) {
    next(e);
  }
}

export async function updateProductAvailability(req, res, next) {
  try {
    const body = {
      ...req.body,
      isAvailable:
        req.body?.isAvailable === undefined
          ? undefined
          : parseBooleanInput(req.body?.isAvailable),
    };

    const v = validateOwnerProductUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const product = await service.updateOwnerProduct(
      req.userId,
      Number(req.params.productId),
      body
    );
    res.json(product);
  } catch (e) {
    next(e);
  }
}

export async function updateOffer(req, res, next) {
  try {
    const v = validateOwnerOfferUpdate(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const offer = await service.updateOwnerOffer(
      req.userId,
      Number(req.params.offerId),
      req.body || {}
    );
    res.json({ offer });
  } catch (e) {
    next(e);
  }
}

export async function deleteProduct(req, res, next) {
  try {
    await service.deleteOwnerProduct(req.userId, Number(req.params.productId));
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function deleteOffer(req, res, next) {
  try {
    await service.deleteOwnerOffer(req.userId, Number(req.params.offerId));
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function listDeliveryAgents(req, res, next) {
  try {
    const data = await service.listDeliveryAgents(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listAccountants(req, res, next) {
  try {
    const data = await service.listAccountants(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listHrStaff(req, res, next) {
  try {
    const data = await service.listHrStaff(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function searchStaffUsers(req, res, next) {
  try {
    const v = validateOwnerStaffSearchQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const data = await service.searchStaffUsers(req.userId, v.value);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

/**
 * ينشئ موظف delivery جديداً تابعاً للمتجر.
 *
 * التشخيص: إذا فشل هذا المسار رغم صحة البيانات افحص أولاً تضارب الهاتف ثم
 * `createUser` ثم `syncCourierDriverAffiliation` في service.
 */
export async function createDeliveryAgent(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };

    const v = validateOwnerDeliveryAgentCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.createDeliveryAgent(req.userId, body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function assignExistingDeliveryAgent(req, res, next) {
  try {
    const v = validateOwnerAssignExistingStaff(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.assignExistingDeliveryAgent(req.userId, req.body.userId);
    res.status(200).json(out);
  } catch (e) {
    next(e);
  }
}

export async function createAccountant(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const v = validateOwnerAccountantCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.createAccountant(req.userId, body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function createHrStaff(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const v = validateOwnerHrCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.createHrStaff(req.userId, body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function assignExistingAccountant(req, res, next) {
  try {
    const v = validateOwnerAssignExistingStaff(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.assignExistingAccountant(req.userId, req.body.userId);
    res.status(200).json(out);
  } catch (e) {
    next(e);
  }
}

export async function assignExistingHrStaff(req, res, next) {
  try {
    const v = validateOwnerAssignExistingStaff(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.assignExistingHrStaff(req.userId, req.body.userId);
    res.status(200).json(out);
  } catch (e) {
    next(e);
  }
}

export async function listCurrentOrders(req, res, next) {
  try {
    const data = await service.listCurrentOrders(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listOrderHistory(req, res, next) {
  try {
    const data = await service.listOrderHistory(req.userId, req.query.date);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

/**
 * يحدّث حالة الطلب من جهة المتجر، بما في ذلك مدد التحضير والتوصيل التقديرية.
 */
export async function updateOrderStatus(req, res, next) {
  try {
    const v = validateOwnerOrderStatusUpdate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.updateOrderStatus(
      req.userId,
      req.params.orderId,
      req.body.status,
      req.body.estimatedPrepMinutes,
      req.body.estimatedDeliveryMinutes
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * يربط الطلب بدلفري محدد أو بنمط إسناد معين من لوحة صاحب المتجر.
 */
export async function assignDelivery(req, res, next) {
  try {
    const v = validateOwnerAssignDelivery(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.assignDelivery(
      req.userId,
      req.params.orderId,
      req.body.deliveryUserId,
      req.body.assignmentMode
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function markOrderItemUnavailable(req, res, next) {
  try {
    const body = {
      unavailableReason: req.body?.unavailableReason,
      unavailableUntil: req.body?.unavailableUntil,
    };
    const v = validateOwnerMarkOrderItemUnavailable(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const product = await service.markOrderItemUnavailable(
      req.userId,
      req.params.orderId,
      req.params.productId,
      body
    );
    res.json({ product });
  } catch (e) {
    next(e);
  }
}

export async function analytics(req, res, next) {
  try {
    const out = await service.ownerAnalytics(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function printOrdersReport(req, res, next) {
  try {
    const out = await service.printOrdersReport(req.userId, req.query?.period);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function settlementSummary(req, res, next) {
  try {
    const out = await service.settlementSummary(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينشئ طلب تسوية/تحصيل مالي لصاحب المتجر.
 */
export async function requestSettlement(req, res, next) {
  try {
    const out = await service.requestSettlement(req.userId, req.body?.note);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}
