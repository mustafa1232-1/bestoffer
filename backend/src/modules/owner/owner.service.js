import { hashPin } from "../../shared/utils/hash.js";
import { markSessionRevoked } from "../../shared/middleware/access-auth.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import { createUser, findUserByPhone, getUserPublicById } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import { createUserSession, pruneUserSessions } from "../auth/auth.repo.js";
import * as analyticsRepo from "../../shared/analytics/commerce-analytics.repo.js";
import * as commerceRepo from "../commerce/commerce.repo.js";
import * as subscriptionsService from "../subscriptions/subscriptions.service.js";
import { getMerchantBillingProfile } from "../commerce/merchant-financial.logic.js";
import * as companyRepo from "../company/company.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import { invalidateOrderListCacheForUser } from "../orders/orders.service.js";
import * as offersRepo from "./merchant-offers.repo.js";
import * as repo from "./owner.repo.js";
import { env } from "../../config/env.js";
import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";
import { createNotification } from "../notifications/notifications.repo.js";
import { AppError } from "../../shared/utils/errors.js";
import {
  buildMerchantOfferLabel,
  computeMerchantOfferState,
} from "./merchant-offers.logic.js";
import { hasPermission } from "../../shared/workspaces/employee-permissions.js";
import {
  applyStoreActivityInternalTemplateToMerchants,
  invalidateMerchantCatalogCache,
  upsertStoreActivityInternalTemplate,
} from "../merchants/merchants.repo.js";
import {
  hasRichProductInput,
  normalizeRichProductPayload,
} from "../products/product-catalog.logic.js";
import { loadProductRichCatalogById } from "../products/products.repo.js";
import crypto from "crypto";
import {
  buildMerchantCapabilities,
  inferActivityTypeFromMerchantType,
  normalizeActivityType,
  normalizeDiscoverySubcategoryList,
  requireActivityConfig,
  requireValidDiscoverySelection,
} from "../merchants/store-activity.registry.js";
import {
  inferCatalogTypeFromName,
  getAllowedCatalogTypesForActivity,
  isCatalogTypeAllowedForActivity,
  normalizeCatalogType,
  resolveCategoryCatalogType,
} from "../merchants/catalog-taxonomy.js";
import {
  activityRequiresDepartment,
  resolveStoreDepartmentForWrite,
} from "../merchants/store-department.logic.js";

/**
 * Purpose: منطق أعمال صاحب المتجر كاملاً: التسجيل، المتجر، المنتجات، العروض، الفريق، الطلبات، والتحصيلات.
 * Used by: `owner.controller.js` وواجهات owner في Flutter.
 * Depends on: auth repo/session helpers، `owner.repo.js`، orders/analytics/commerce repos، والإشعارات.
 * Critical notes: الملف يجمع عمليات متعددة التأثير وتغيّر أكثر من جدول؛ بعض المسارات هنا حساسة جداً لصلاحيات الدور وتناسق الهواتف.
 * Maintenance notes: إذا ظهر خلل في owner flow فابدأ بتحديد المجال أولاً (merchant/catalog/staff/orders/settlement) ثم اتبع repo المستخدم داخل الدالة المقابلة هنا.
 */

/**
 * يطبع record المستخدم القادم من قاعدة البيانات إلى الشكل الذي تستهلكه الواجهة.
 */
function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    role: u.role,
    isSuperAdmin: u.is_super_admin === true,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
    imageUrl: u.image_url,
  };
}

/**
 * يطبع merchant row إلى الشكل القياسي المستخدم في API owner.
 */
export function mapMerchant(m) {
  const discoverySubcategories = Array.isArray(m.discovery_subcategories)
    ? m.discovery_subcategories
        .map((value) => normalizeOptional(value)?.toLowerCase())
        .filter(Boolean)
    : [];
  const legacyDiscovery = normalizeOptional(m.discovery_subcategory)?.toLowerCase();
  if (legacyDiscovery && !discoverySubcategories.includes(legacyDiscovery)) {
    discoverySubcategories.unshift(legacyDiscovery);
  }
  return {
    id: m.id,
    name: m.name,
    type: m.type,
    activityType: m.activity_type || null,
    department: m.store_department || null,
    discoverySubcategory: m.discovery_subcategory || null,
    discoverySubcategories,
    discoverySelectAll: m.discovery_select_all === true,
    serviceFlags:
      m.service_flags_json && typeof m.service_flags_json === "object"
        ? m.service_flags_json
        : {},
    supportsChat: m.supports_chat === true,
    supportsAttachments: m.supports_attachments === true,
    supportsPharmacyWorkflow: m.supports_pharmacy_workflow === true,
    badges: Array.isArray(m.badges_json) ? m.badges_json : [],
    description: m.description,
    phone: m.phone,
    imageUrl: m.image_url,
    // Storefront contract (nullable = unknown; never coerced to 0).
    logoUrl: m.logo_url || null,
    coverImageUrl: m.cover_image_url || null,
    deliveryEtaMinMinutes:
      m.delivery_eta_min_minutes == null
        ? null
        : Number(m.delivery_eta_min_minutes),
    deliveryEtaMaxMinutes:
      m.delivery_eta_max_minutes == null
        ? null
        : Number(m.delivery_eta_max_minutes),
    deliveryFee: m.delivery_fee == null ? null : Number(m.delivery_fee),
    minimumOrder: m.minimum_order == null ? null : Number(m.minimum_order),
    isVerified: m.is_verified === true,
    nextOpenAt: m.next_open_at || null,
    isOpen: m.is_open,
    isApproved: m.is_approved,
    approvalStatus: m.approval_status,
    approvedByUserId: m.approved_by_user_id,
    approvedAt: m.approved_at,
    ownerUserId: m.owner_user_id,
    tagline: m.tagline,
    workingHours: m.working_hours,
    serviceAreaNote: m.service_area_note,
    financialTermsSentAt: m.financial_terms_sent_at,
    financialTermsAcceptedAt: m.financial_terms_accepted_at,
    financialTermsRejectedAt: m.financial_terms_rejected_at,
    financialTermsSnapshot:
      m.financial_terms_snapshot_json &&
      typeof m.financial_terms_snapshot_json === "object"
        ? m.financial_terms_snapshot_json
        : null,
    financialTermsRejectionNote: m.financial_terms_rejection_note,
    createdAt: m.created_at,
    updatedAt: m.updated_at,
  };
}

function normalizeOptional(v) {
  if (v === undefined || v === null) return null;
  const out = String(v).trim();
  return out.length ? out : null;
}

function normalizeRole(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizeIsoDateOrNull(v) {
  const normalized = normalizeOptional(v);
  if (normalized === null) return null;
  const parsed = new Date(normalized);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizePhone(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

async function ensureMerchantPermission(ownerUserId, merchantId, permission) {
  const resolvedMerchantId = Number(merchantId);
  if (!Number.isInteger(resolvedMerchantId) || resolvedMerchantId <= 0) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }

  const ownerMerchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
  if (ownerMerchant && Number(ownerMerchant.id) === resolvedMerchantId) {
    return;
  }

  const profile = await repo.findEmployeeProfileForMerchant({
    merchantId: resolvedMerchantId,
    employeeUserId: Number(ownerUserId),
  });
  if (!profile || profile.is_active !== true || profile.archived_at) {
    throw new AppError("FORBIDDEN_MERCHANT_EMPLOYEE_ONLY", { status: 403 });
  }
  if (!hasPermission(profile.permissions_json, permission)) {
    throw new AppError("FORBIDDEN_MERCHANT_PERMISSION", { status: 403 });
  }
}

async function ensureMerchantAnyPermission(ownerUserId, merchantId, permissions) {
  const requiredPermissions = Array.isArray(permissions)
    ? permissions.map((permission) => String(permission || "").trim()).filter(Boolean)
    : [String(permissions || "").trim()].filter(Boolean);
  if (requiredPermissions.length === 0) {
    throw new AppError("FORBIDDEN_MERCHANT_PERMISSION", { status: 403 });
  }

  const resolvedMerchantId = Number(merchantId);
  if (!Number.isInteger(resolvedMerchantId) || resolvedMerchantId <= 0) {
    throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  }

  const ownerMerchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
  if (ownerMerchant && Number(ownerMerchant.id) === resolvedMerchantId) {
    return;
  }

  const profile = await repo.findEmployeeProfileForMerchant({
    merchantId: resolvedMerchantId,
    employeeUserId: Number(ownerUserId),
  });
  if (!profile || profile.is_active !== true || profile.archived_at) {
    throw new AppError("FORBIDDEN_MERCHANT_EMPLOYEE_ONLY", { status: 403 });
  }

  if (
    !requiredPermissions.some((permission) =>
      hasPermission(profile.permissions_json, permission)
    )
  ) {
    throw new AppError("FORBIDDEN_MERCHANT_PERMISSION", { status: 403 });
  }
}

function normalizeOrderStatus(value) {
  return String(value || "").trim().toLowerCase();
}

function requiredOrderStatusPermissions(nextStatus) {
  switch (normalizeOrderStatus(nextStatus)) {
    case "approved":
      return ["accept_orders", "change_order_status"];
    case "preparing":
    case "ready_for_delivery":
      return ["prepare_orders", "change_order_status"];
    case "cancelled":
      return ["reject_orders", "change_order_status"];
    default:
      return ["change_order_status"];
  }
}

function nextProductAvailabilitySnapshot(currentProduct, dto = {}) {
  return snapshotAvailability({
    isAvailable:
      dto.isAvailable === undefined
        ? currentProduct?.is_available
        : dto.isAvailable,
    unavailableReason:
      dto.unavailableReason === undefined
        ? currentProduct?.unavailable_reason
        : dto.unavailableReason,
    unavailableUntil:
      dto.unavailableUntil === undefined
        ? currentProduct?.unavailable_until
        : dto.unavailableUntil,
  });
}

function productAvailabilityChanged(currentProduct, dto = {}) {
  return snapshotsDiffer(
    snapshotAvailability(currentProduct),
    nextProductAvailabilitySnapshot(currentProduct, dto)
  );
}

function toNumberOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toPositiveIntOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function snapshotAvailability(entity) {
  if (!entity) {
    return {
      isAvailable: true,
      unavailableReason: null,
      unavailableUntil: null,
    };
  }
  return {
    isAvailable: entity.isAvailable !== false && entity.is_available !== false,
    unavailableReason: normalizeOptional(
      entity.unavailableReason ?? entity.unavailable_reason
    ),
    unavailableUntil: normalizeIsoDateOrNull(
      entity.unavailableUntil ?? entity.unavailable_until
    ),
  };
}

function availabilityKey(entity, index = 0) {
  if (entity?.id != null) return `id:${Number(entity.id)}`;
  return `signature:${String(entity?.signature || index)}`;
}

function snapshotsDiffer(before, after) {
  return (
    before.isAvailable !== after.isAvailable ||
    before.unavailableReason !== after.unavailableReason ||
    before.unavailableUntil !== after.unavailableUntil
  );
}

function buildAvailabilityAuditValue(snapshot) {
  return {
    isAvailable: snapshot.isAvailable,
    unavailableReason: snapshot.unavailableReason,
    unavailableUntil: snapshot.unavailableUntil,
  };
}

async function insertAvailabilityAuditLog({
  merchantId,
  productId,
  actorUserId,
  actorRole = "owner",
  actionKey,
  summary,
  oldValue = {},
  newValue = {},
  variantId = null,
  reason = null,
  unavailableUntil = null,
  note = null,
}) {
  await companyRepo.insertInventoryAuditLog({
    merchantId,
    productId,
    actorUserId,
    actorRole,
    actorContext: "owner_portal",
    actionKey,
    summary,
    variantId,
    reason,
    unavailableUntil,
    oldValue,
    newValue,
    note,
  });
}

async function recordProductAvailabilityChange({
  actorUserId,
  merchantId,
  productId,
  productName,
  beforeProduct,
  afterProduct,
  beforeRichCatalog,
  afterRichCatalog,
}) {
  const before = snapshotAvailability(beforeProduct);
  const after = snapshotAvailability(afterProduct);
  const records = [];

  if (snapshotsDiffer(before, after)) {
    records.push(
      insertAvailabilityAuditLog({
        merchantId,
        productId,
        actorUserId,
        actionKey: "owner.product.availability.updated",
        summary: `${productName || "Product"} availability updated`,
        oldValue: buildAvailabilityAuditValue(before),
        newValue: buildAvailabilityAuditValue(after),
        reason: after.unavailableReason,
        unavailableUntil: after.unavailableUntil,
      })
    );
  }

  const beforeVariants = Array.isArray(beforeRichCatalog?.variants)
    ? beforeRichCatalog.variants
    : [];
  const afterVariants = Array.isArray(afterRichCatalog?.variants)
    ? afterRichCatalog.variants
    : [];
  const beforeByKey = new Map(
    beforeVariants.map((variant, index) => [
      availabilityKey(variant, index),
      snapshotAvailability(variant),
    ])
  );

  afterVariants.forEach((variant, index) => {
    const afterVariant = snapshotAvailability(variant);
    const key = availabilityKey(variant, index);
    const beforeVariant = beforeByKey.get(key) || {
      isAvailable: true,
      unavailableReason: null,
      unavailableUntil: null,
    };
    if (!snapshotsDiffer(beforeVariant, afterVariant)) return;
    records.push(
      insertAvailabilityAuditLog({
        merchantId,
        productId,
        actorUserId,
        variantId: variant.id ?? null,
        actionKey: "owner.product.variant.availability.updated",
        summary: `${productName || "Product"} variant availability updated`,
        oldValue: buildAvailabilityAuditValue(beforeVariant),
        newValue: buildAvailabilityAuditValue(afterVariant),
        reason: afterVariant.unavailableReason,
        unavailableUntil: afterVariant.unavailableUntil,
      })
    );
  });

  if (records.length > 0) {
    const settled = await Promise.allSettled(records);
    const rejected = settled.filter((entry) => entry.status === "rejected");
    if (rejected.length > 0) {
      console.error("AVAILABILITY_AUDIT_LOG_FAILED", rejected[0].reason);
    }
  }
}

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function assertValidBasmayaAddress(address) {
  const validation = validateBasmayaAddress(address);
  if (!validation.ok) {
    const err = new Error("INVALID_BASMAYA_ADDRESS");
    err.status = 400;
    err.fields = validation.errors;
    throw err;
  }
  return validation.normalized;
}

function resolveOwnerAddress(dto) {
  const block = normalizeOptional(dto.block);
  const buildingNumber = normalizeOptional(dto.buildingNumber);
  const apartment = normalizeOptional(dto.apartment);
  const providedCount = [block, buildingNumber, apartment].filter(Boolean).length;

  if (providedCount === 0) {
    return {
      block: "A1",
      buildingNumber: "A101",
      apartment: "101",
    };
  }

  if (providedCount < 3) {
    const err = new Error("INVALID_BASMAYA_ADDRESS");
    err.status = 400;
    err.fields = ["block", "buildingNumber", "apartment"];
    throw err;
  }

  return assertValidBasmayaAddress({ block, buildingNumber, apartment });
}

function mapCategory(c) {
  return {
    id: c.id,
    merchantId: c.merchant_id,
    name: c.name,
    catalogType: resolveCategoryCatalogType(c),
    sortOrder: c.sort_order,
    createdAt: c.created_at,
    updatedAt: c.updated_at,
  };
}

function resolveMerchantActivityType(merchant) {
  return (
    normalizeActivityType(merchant?.activityType ?? merchant?.activity_type) ||
    inferActivityTypeFromMerchantType(merchant?.type) ||
    "market"
  );
}

function throwCategoryScopeError(field) {
  throw new AppError("VALIDATION_ERROR", {
    status: 400,
    details: {
      fields: {
        [field]: "INVALID_CATEGORY_FOR_STORE_TYPE",
      },
    },
  });
}

function assertCategoryCatalogScope(activityType, catalogType, field = "catalogType") {
  const allowedCatalogTypes = getAllowedCatalogTypesForActivity(activityType);
  const isAllowed =
    allowedCatalogTypes.length > 0
      ? isCatalogTypeAllowedForActivity(activityType, catalogType)
      : normalizeCatalogType(catalogType, null) === "generic";
  if (!isAllowed) {
    throwCategoryScopeError(field);
  }
}

function buildCatalogTemplateCode(name, catalogType) {
  const normalized = String(name || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (normalized) return normalized.slice(0, 120);
  const digest = crypto
    .createHash("sha1")
    .update(`${catalogType || "generic"}:${String(name || "").trim()}`)
    .digest("hex")
    .slice(0, 10);
  return `custom_${catalogType || "generic"}_${digest}`.slice(0, 120);
}

// eslint-disable-next-line no-unused-vars
function inferCatalogType(name) {
  const value = String(name || "").trim().toLowerCase();
  if (["cloths", "clothes", "clothing", "fashion", "ملابس", "الملابس"].includes(value)) return "clothes";
  if (["furniture", "اثاث", "أثاث", "الاثاث", "الأثاث"].includes(value)) return "furniture";
  if (["electronics", "electrical", "الكترونيات", "إلكترونيات", "كهربائيات"].includes(value)) return "electronics";
  if (["restaurant", "restaurants", "food", "مطعم", "مطاعم"].includes(value)) return "restaurant";
  if (["grocery", "groceries", "supermarket", "بقالة", "مواد غذائية"].includes(value)) return "grocery";
  return "generic";
}

/**
 * يطبع offer row ويضم المنتجات المرتبطة به مع label/status المشتقين.
 */
function mapOffer(offer) {
  return {
    id: Number(offer.id),
    merchantId: Number(offer.merchant_id),
    title: offer.title,
    description: offer.description || null,
    offerType: offer.offer_type,
    discountValue:
      offer.discount_value == null ? null : Number(offer.discount_value),
    buyQuantity: offer.buy_quantity == null ? null : Number(offer.buy_quantity),
    getQuantity: offer.get_quantity == null ? null : Number(offer.get_quantity),
    startsAt: offer.starts_at || null,
    endsAt: offer.ends_at || null,
    status: computeMerchantOfferState(offer),
    configuredStatus: offer.status,
    maxUsage: offer.max_usage == null ? null : Number(offer.max_usage),
    createdAt: offer.created_at || null,
    updatedAt: offer.updated_at || null,
    label: buildMerchantOfferLabel(offer),
    products: Array.isArray(offer.products)
      ? offer.products.map((product) => ({
          id: Number(product.id),
          name: product.name,
          price: Number(product.price || 0),
          discountedPrice:
            product.discountedPrice == null
              ? null
              : Number(product.discountedPrice),
          offerLabel: product.offerLabel || null,
          isAvailable: product.isAvailable !== false,
        }))
      : [],
  };
}

function mapDeliveryAgent(row) {
  return {
    id: Number(row.id),
    fullName: row.full_name,
    phone: row.phone,
    imageUrl: row.image_url || null,
    createdAt: row.created_at || null,
  };
}

function mapAccountant(row) {
  return {
    id: Number(row.id),
    fullName: row.full_name,
    phone: row.phone,
    imageUrl: row.image_url || null,
    createdAt: row.created_at || null,
  };
}

function mapHrStaff(row) {
  return {
    id: Number(row.id),
    fullName: row.full_name,
    phone: row.phone,
    imageUrl: row.image_url || null,
    createdAt: row.created_at || null,
  };
}

function mapStaffSearchUser(row) {
  return {
    id: Number(row.id),
    fullName: row.full_name,
    phone: row.phone,
    role: row.role,
    imageUrl: row.image_url || null,
    isTaxiCaptain: row.is_taxi_captain === true,
    isAccountDisabled: row.is_account_disabled === true,
  };
}

/**
 * يتحقق أن المستخدم المرشح لربطه كموظف صالح لهذا النوع من الأدوار.
 *
 * WARNING:
 * - لا تعدل شروط الأهلية هنا بلا مراجعة matrix الأدوار، لأن هذه الدالة تمنع
 *   escalation غير مباشر عند إعادة استخدام حسابات موجودة.
 */
function assertValidStaffCandidate(user, { targetRole }) {
  if (!user) {
    const err = new Error("USER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (user.is_account_disabled === true) {
    const err = new Error("USER_ACCOUNT_DISABLED");
    err.status = 409;
    throw err;
  }
  if (user.is_taxi_captain === true) {
    const err = new Error("TAXI_CAPTAIN_CANNOT_BE_ASSIGNED");
    err.status = 409;
    throw err;
  }
  const currentRole = String(user.role || "").toLowerCase();
  if (["owner", "admin", "deputy_admin", "call_center"].includes(currentRole)) {
    const err = new Error("USER_ROLE_NOT_ELIGIBLE");
    err.status = 409;
    throw err;
  }
  if (targetRole === "delivery" && currentRole === "accountant") {
    const err = new Error("ACCOUNTANT_CANNOT_SWITCH_TO_DELIVERY_DIRECTLY");
    err.status = 409;
    throw err;
  }
}

/**
 * ينشئ access session موحدة لحساب owner بعد التسجيل.
 *
 * Side effects:
 * - إنشاء session row
 * - تقليم الجلسات القديمة حسب إعدادات `env.authMaxActiveSessionsPerUser`
 */
async function issueOwnerSession(user, deviceContext = {}) {
  const tokenJti = crypto.randomBytes(18).toString("base64url");
  const refreshToken = crypto.randomBytes(32).toString("base64url");
  const deviceSessionId = crypto.randomBytes(24).toString("base64url");
  const deviceRecoverySecret = crypto.randomBytes(32).toString("base64url");
  const recoverySecretHash = crypto
    .createHash("sha256")
    .update(deviceRecoverySecret)
    .digest("hex");
  const expiresAt = new Date(
    Date.now() + Math.max(1, Number(env.authSessionTtlDays || 30)) * 24 * 60 * 60 * 1000
  );

  const session = await createUserSession({
    userId: user.id,
    refreshToken,
    tokenJti,
    deviceFingerprint: deviceContext.deviceFingerprint || null,
    userAgent: deviceContext.userAgent || null,
    ipAddress: deviceContext.ipAddress || null,
    expiresAt,
    accessExpiresAt: null,
    deviceSessionId,
    recoverySecretHash,
    appSurface: "store",
  });

  const token = signAccessToken(
    {
      id: user.id,
      role: user.role || "owner",
      isSuperAdmin: user.is_super_admin === true,
    },
    {
      sessionId: session?.id || null,
      tokenJti,
      deviceFingerprint: deviceContext.deviceFingerprint || null,
    }
  );

  const pruned = await pruneUserSessions(user.id, {
    maxActive: env.authMaxActiveSessionsPerUser,
  });
  if (Array.isArray(pruned?.revokedSessionIds) && pruned.revokedSessionIds.length > 0) {
    await Promise.all(
      pruned.revokedSessionIds.map((revokedSessionId) =>
        markSessionRevoked(revokedSessionId)
      )
    );
  }

  return {
    token,
    refreshToken,
    sessionId: session?.id || null,
    deviceSessionId,
    deviceRecoverySecret,
  };
}

/**
 * يسجل صاحب متجر جديداً مع merchant مرتبط به في transaction repo واحدة.
 *
 * Parameters:
 * - `dto`: بيانات التسجيل والعنوان والموافقة التحليلية.
 * - `deviceContext`: بصمة الجهاز ومعلومات الجلسة المستخرجة من الطلب.
 *
 * Failure modes:
 * - `PHONE_EXISTS`
 * - `INVALID_BASMAYA_ADDRESS`
 * - `ANALYTICS_CONSENT_REQUIRED`
 * - `MERCHANT_SERVICE_AREA_NOTE_REQUIRED`
 */
// إنشاء حساب صاحب متجر + المتجر المرتبط به (بدون إصدار جلسة). يُعاد استخدامه
// في التسجيل الذاتي (registerOwner) وفي إنشاء الحساب من قبل الإدمن حيث تُضاف
// الشروط المالية ويُعتمد المتجر مباشرةً.
export async function createOwnerAccountWithMerchant(dto) {
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const address = resolveOwnerAddress(dto);
  // Explicit category required — requireActivityConfig throws if missing/invalid
  // (no silent inference from merchant base type for new stores).
  const requestedActivityType = normalizeActivityType(dto.merchantActivityType);
  const activityConfig = await requireActivityConfig(requestedActivityType);
  // Fashion/clothing stores must declare a customer department (رجالي / نسائي).
  // Non-fashion stores keep department null. Throws VALIDATION_ERROR otherwise.
  const merchantDepartment = resolveStoreDepartmentForWrite({
    activityType: activityConfig.activityType,
    department: dto.merchantDepartment,
  });
  const normalizedDiscoverySubcategoriesInput = normalizeDiscoverySubcategoryList(
    dto.merchantDiscoverySubcategories
  );
  const hasLegacyActivityFallbackInput =
    !normalizeOptional(dto.merchantActivityType) &&
    normalizeOptional(dto.merchantType) != null;
  const shouldFallbackToSelectAllDiscovery =
    activityConfig.hasDiscoverySubcategories === true &&
    hasLegacyActivityFallbackInput &&
    normalizeOptional(dto.merchantDiscoverySubcategory) == null &&
    normalizedDiscoverySubcategoriesInput.length === 0 &&
    dto.merchantDiscoverySelectAll !== true;
  const requestedMerchantType = normalizeOptional(dto.merchantType);
  if (
    requestedMerchantType &&
    requestedMerchantType !== String(activityConfig.baseType || "").trim()
  ) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.fields = ["merchantType"];
    throw err;
  }
  const merchantDiscoverySelection = await requireValidDiscoverySelection(
    activityConfig.activityType,
    {
      discoverySubcategory: dto.merchantDiscoverySubcategory,
      discoverySubcategories: normalizedDiscoverySubcategoriesInput,
      discoverySelectAll:
        dto.merchantDiscoverySelectAll === true ||
        shouldFallbackToSelectAllDiscovery,
    }
  );
  const merchantCapabilities = buildMerchantCapabilities(activityConfig, {
    serviceFlags:
      dto.merchantServiceFlags &&
      typeof dto.merchantServiceFlags === "object" &&
      !Array.isArray(dto.merchantServiceFlags)
        ? dto.merchantServiceFlags
        : undefined,
    badges: Array.isArray(dto.merchantBadges) ? dto.merchantBadges : undefined,
    supportsChat:
      dto.merchantSupportsChat === undefined
        ? undefined
        : dto.merchantSupportsChat === true,
    supportsAttachments:
      dto.merchantSupportsAttachments === undefined
        ? undefined
        : dto.merchantSupportsAttachments === true,
    supportsPharmacyWorkflow:
      dto.merchantSupportsPharmacyWorkflow === undefined
        ? undefined
        : dto.merchantSupportsPharmacyWorkflow === true,
  });
  const merchantServiceAreaNote =
    normalizeOptional(dto.merchantServiceAreaNote) ||
    normalizeOptional(dto.block) ||
    "Basmaya";
  const analyticsConsentAccepted = normalizeConsentAccepted(
    dto.analyticsConsentAccepted
  );
  const analyticsConsentVersion =
    typeof dto.analyticsConsentVersion === "string" &&
    dto.analyticsConsentVersion.trim().length > 0
      ? dto.analyticsConsentVersion.trim().slice(0, 32)
      : "analytics_v1";

  if (!analyticsConsentAccepted) {
    const err = new Error("ANALYTICS_CONSENT_REQUIRED");
    err.status = 400;
    throw err;
  }

  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(pin);
  const merchantName = dto.merchantName.trim();
  const accountName = normalizeOptional(dto.fullName) || merchantName;
  const merchantPhone = normalizePhone(dto.merchantPhone || phone) || phone;
  const out = await runWithGeneratedAppUserUsername({
    fullName: accountName,
    phone,
    execute: (username) =>
      repo.createOwnerWithMerchant({
        fullName: accountName,
        username,
        phone,
        pinHash,
        block: address.block,
        buildingNumber: address.buildingNumber,
        apartment: address.apartment,
        ownerImageUrl: normalizeOptional(dto.ownerImageUrl),
        merchantName,
        merchantType: activityConfig.baseType,
        merchantActivityType: activityConfig.activityType,
        merchantDepartment,
        merchantDiscoverySubcategory:
          merchantDiscoverySelection.legacyDiscoverySubcategory,
        merchantDiscoverySubcategories:
          merchantDiscoverySelection.discoverySubcategories,
        merchantDiscoverySelectAll:
          merchantDiscoverySelection.discoverySelectAll === true,
        merchantDescription: normalizeOptional(dto.merchantDescription),
        merchantPhone,
        merchantImageUrl: normalizeOptional(dto.merchantImageUrl),
        merchantTagline: normalizeOptional(dto.merchantTagline),
        merchantWorkingHours: normalizeOptional(dto.merchantWorkingHours),
        merchantServiceAreaNote,
        merchantServiceFlags: merchantCapabilities.serviceFlags,
        merchantSupportsChat: merchantCapabilities.supportsChat === true,
        merchantSupportsAttachments:
          merchantCapabilities.supportsAttachments === true,
        merchantSupportsPharmacyWorkflow:
          merchantCapabilities.supportsPharmacyWorkflow === true,
        merchantBadges: merchantCapabilities.badges,
        analyticsConsentGranted: true,
        analyticsConsentVersion,
        analyticsConsentGrantedAt: new Date(),
        chatQualityReviewConsent: true,
      }),
  });

  return out;
}

export async function registerOwner(dto, deviceContext = {}) {
  const out = await createOwnerAccountWithMerchant(dto);

  const session = await issueOwnerSession(out.user, deviceContext);

  return {
    token: session.token,
    refreshToken: session.refreshToken,
    sessionId: session.sessionId,
    deviceSessionId: session.deviceSessionId,
    deviceRecoverySecret: session.deviceRecoverySecret,
    user: mapUser(out.user),
    merchant: mapMerchant(out.merchant),
  };
}

/**
 * يعيد المتجر المرتبط بصاحب المتجر الحالي أو يرمي `MERCHANT_NOT_FOUND`.
 */
export async function getOwnerMerchant(ownerUserId) {
  const merchant =
    (await repo.findMerchantByOwnerUserId(ownerUserId)) ||
    (await repo.findMerchantByEmployeeUserId(ownerUserId));
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return mapMerchant(merchant);
}

/**
 * يعتمد الشروط المالية من جهة صاحب المتجر ويرسل إشعارات للطرفين المتأثرين.
 *
 * Side effects:
 * - تحديث حالة الشروط المالية داخل commerce repo
 * - إنشاء إشعارات للمالك وللإدارة إن لزم
 */
export async function acceptOwnerFinancialTerms(ownerUserId) {
  const out = await commerceRepo.acceptMerchantFinancialTermsByOwner({
    ownerUserId: Number(ownerUserId),
  });
  await createNotification({
    userId: Number(out.merchant?.owner_user_id || ownerUserId),
    type: "owner_merchant_approved",
    title: "تم تفعيل المتجر",
    body: `تم اعتماد متجرك ${out.merchant?.name || ""} بعد قبول الشروط المالية.`,
    merchantId: Number(out.merchant?.id || 0) || null,
    payload: {
      merchantId: Number(out.merchant?.id || 0) || null,
      approvalStatus: "approved",
      target: "owner_dashboard",
    },
  }).catch(() => {});
  if (out.merchant?.approved_by_user_id) {
    await createNotification({
      userId: Number(out.merchant.approved_by_user_id),
      type: "admin_merchant_financial_terms_accepted",
      title: "وافق المتجر على الشروط المالية",
      body: `وافق صاحب متجر ${out.merchant?.name || ""} على الشروط المالية وتم تفعيل المتجر.`,
      merchantId: Number(out.merchant?.id || 0) || null,
      payload: {
        merchantId: Number(out.merchant?.id || 0) || null,
        approvalStatus: "approved",
        target: "admin_approval_inbox",
      },
    }).catch(() => {});
  }
  return {
    merchant: mapMerchant(out.merchant),
    financialTerms: out.financialTerms,
  };
}

/**
 * يرفض الشروط المالية ويعيد الملف إلى مراجعة الإدارة مع إشعار للجهة التي أرسلت الشروط.
 */
export async function rejectOwnerFinancialTerms(ownerUserId, note = null) {
  const out = await commerceRepo.rejectMerchantFinancialTermsByOwner({
    ownerUserId: Number(ownerUserId),
    note,
  });
  if (out.merchant?.financial_terms_sent_by_user_id) {
    await createNotification({
      userId: Number(out.merchant.financial_terms_sent_by_user_id),
      type: "admin_merchant_financial_terms_rejected",
      title: "رفض المتجر الشروط المالية",
      body: `رفض صاحب متجر ${out.merchant?.name || ""} الشروط المالية وأعاد الطلب للمراجعة.`,
      merchantId: Number(out.merchant?.id || 0) || null,
      payload: {
        merchantId: Number(out.merchant?.id || 0) || null,
        approvalStatus: "pending_admin_review",
        target: "admin_approval_inbox",
      },
    }).catch(() => {});
  }
  return {
    merchant: mapMerchant(out.merchant),
    financialTerms: out.financialTerms,
  };
}

/**
 * يحدّث بيانات المتجر الأساسية بعد تطبيع الحقول الاختيارية والهواتف.
 */
// Guard rails for storefront delivery economics. Minutes are integers; fees
// are non-negative amounts with a sane cap; max ETA must be >= min ETA. A field
// left undefined is not touched; passing null explicitly clears it (delivery
// disabled). Missing values stay unknown — never fabricated.
const STOREFRONT_MAX_ETA_MINUTES = 600; // 10 hours upper bound
const STOREFRONT_MAX_FEE = 1_000_000; // IQD sane cap

function coerceStorefrontMinutes(value, field, errors) {
  if (value === null) return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || n > STOREFRONT_MAX_ETA_MINUTES) {
    errors.push(field);
    return undefined;
  }
  return n;
}

function coerceStorefrontAmount(value, field, errors) {
  if (value === null) return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > STOREFRONT_MAX_FEE) {
    errors.push(field);
    return undefined;
  }
  return n;
}

export function applyStorefrontDeliveryPatch({ dto, currentMerchant, patch }) {
  const errors = [];

  let etaMin;
  let etaMax;
  if (dto.deliveryEtaMinMinutes !== undefined) {
    etaMin = coerceStorefrontMinutes(
      dto.deliveryEtaMinMinutes,
      "deliveryEtaMinMinutes",
      errors
    );
  }
  if (dto.deliveryEtaMaxMinutes !== undefined) {
    etaMax = coerceStorefrontMinutes(
      dto.deliveryEtaMaxMinutes,
      "deliveryEtaMaxMinutes",
      errors
    );
  }

  // Cross-field: resolve the effective min/max (falling back to stored values)
  // and require max >= min when both are known.
  const effectiveMin =
    etaMin !== undefined
      ? etaMin
      : currentMerchant?.delivery_eta_min_minutes ?? null;
  const effectiveMax =
    etaMax !== undefined
      ? etaMax
      : currentMerchant?.delivery_eta_max_minutes ?? null;
  if (
    effectiveMin !== null &&
    effectiveMax !== null &&
    Number(effectiveMax) < Number(effectiveMin)
  ) {
    errors.push("deliveryEtaRange");
  }

  if (dto.deliveryFee !== undefined) {
    const fee = coerceStorefrontAmount(dto.deliveryFee, "deliveryFee", errors);
    if (fee !== undefined) patch.deliveryFee = fee;
  }
  if (dto.minimumOrder !== undefined) {
    const min = coerceStorefrontAmount(
      dto.minimumOrder,
      "minimumOrder",
      errors
    );
    if (min !== undefined) patch.minimumOrder = min;
  }

  if (errors.length) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.fields = errors;
    throw err;
  }

  if (etaMin !== undefined) patch.deliveryEtaMinMinutes = etaMin;
  if (etaMax !== undefined) patch.deliveryEtaMaxMinutes = etaMax;
}

export async function updateOwnerMerchant(ownerUserId, dto) {
  const currentMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    Number(currentMerchant.id),
    "manage_store_profile"
  );
  if (!currentMerchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const patch = {};
  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.type !== undefined) patch.type = dto.type;

  const nextActivityType =
    dto.activityType !== undefined
      ? normalizeOptional(dto.activityType)?.toLowerCase() || null
      : normalizeOptional(currentMerchant.activity_type)?.toLowerCase() || null;
  if (!nextActivityType) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.fields = ["activityType"];
    throw err;
  }

  const activityConfig = await requireActivityConfig(nextActivityType);
  const nextType =
    dto.type !== undefined
      ? normalizeOptional(dto.type)
      : normalizeOptional(currentMerchant.type);
  if (
    nextType &&
    normalizeOptional(activityConfig.baseType) &&
    nextType !== normalizeOptional(activityConfig.baseType)
  ) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.fields = ["type"];
    throw err;
  }

  patch.activityType = nextActivityType;

  // Department (رجالي / نسائي) for fashion stores.
  if (activityRequiresDepartment(nextActivityType)) {
    if (dto.department !== undefined) {
      // Explicit change -> strict validation (men/women/unisex only).
      patch.storeDepartment = resolveStoreDepartmentForWrite({
        activityType: nextActivityType,
        department: dto.department,
      });
    } else if (currentMerchant.store_department == null) {
      // Legacy fashion store never classified -> must classify before saving.
      const err = new Error("VALIDATION_ERROR");
      err.status = 400;
      err.fields = ["department"];
      err.details = { fields: { department: "DEPARTMENT_REQUIRED" } };
      throw err;
    }
    // else: keep the existing department (including 'needs_review') so
    // unrelated edits are not blocked.
  } else if (dto.activityType !== undefined) {
    // Switched away from fashion -> department no longer applies.
    patch.storeDepartment = null;
  }

  const hasDiscoveryUpdate =
    dto.discoverySubcategory !== undefined ||
    dto.discoverySubcategories !== undefined ||
    dto.discoverySelectAll !== undefined ||
    dto.activityType !== undefined;

  let discoverySelection = null;
  if (hasDiscoveryUpdate) {
    const existingDiscoverySubcategories = normalizeDiscoverySubcategoryList(
      currentMerchant.discovery_subcategories
    );
    const existingLegacyDiscovery = normalizeOptional(
      currentMerchant.discovery_subcategory
    )?.toLowerCase();
    if (
      existingLegacyDiscovery &&
      !existingDiscoverySubcategories.includes(existingLegacyDiscovery)
    ) {
      existingDiscoverySubcategories.unshift(existingLegacyDiscovery);
    }
    discoverySelection = await requireValidDiscoverySelection(
      nextActivityType,
      {
        discoverySubcategory:
          dto.discoverySubcategory !== undefined
            ? dto.discoverySubcategory
            : existingLegacyDiscovery,
        discoverySubcategories:
          dto.discoverySubcategories !== undefined
            ? normalizeDiscoverySubcategoryList(dto.discoverySubcategories)
            : existingDiscoverySubcategories,
        discoverySelectAll:
          dto.discoverySelectAll !== undefined
            ? dto.discoverySelectAll === true
            : currentMerchant.discovery_select_all === true,
      }
    );
    patch.discoverySubcategory = discoverySelection.legacyDiscoverySubcategory;
    patch.discoverySelectAll = discoverySelection.discoverySelectAll === true;
  }
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.phone !== undefined) {
    const normalizedPhone = normalizePhone(dto.phone);
    patch.phone = normalizedPhone || normalizeOptional(dto.phone);
  }
  if (dto.imageUrl !== undefined) patch.imageUrl = normalizeOptional(dto.imageUrl);
  if (dto.isOpen !== undefined) patch.isOpen = dto.isOpen;
  if (dto.tagline !== undefined) patch.tagline = normalizeOptional(dto.tagline);
  if (dto.workingHours !== undefined) patch.workingHours = normalizeOptional(dto.workingHours);
  if (dto.serviceAreaNote !== undefined) {
    patch.serviceAreaNote = normalizeOptional(dto.serviceAreaNote);
  }
  if (dto.serviceFlags !== undefined) {
    patch.serviceFlags =
      dto.serviceFlags && typeof dto.serviceFlags === "object" && !Array.isArray(dto.serviceFlags)
        ? dto.serviceFlags
        : {};
  }
  if (dto.supportsChat !== undefined) patch.supportsChat = dto.supportsChat === true;
  if (dto.supportsAttachments !== undefined) {
    patch.supportsAttachments = dto.supportsAttachments === true;
  }
  if (dto.supportsPharmacyWorkflow !== undefined) {
    patch.supportsPharmacyWorkflow = dto.supportsPharmacyWorkflow === true;
  }
  if (dto.badges !== undefined) {
    patch.badges = Array.isArray(dto.badges) ? dto.badges : [];
  }

  // Storefront contract fields (logo, cover, delivery ETA/fee, min order).
  if (dto.logoUrl !== undefined) patch.logoUrl = normalizeOptional(dto.logoUrl);
  if (dto.coverImageUrl !== undefined) {
    patch.coverImageUrl = normalizeOptional(dto.coverImageUrl);
  }
  applyStorefrontDeliveryPatch({ dto, currentMerchant, patch });

  const merchant = await repo.updateOwnerMerchant(ownerUserId, patch);
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  if (discoverySelection) {
    await repo.replaceMerchantDiscoverySubcategories(
      Number(merchant.id),
      discoverySelection.discoverySubcategories
    );
  }

  return mapMerchant(merchant);
}

export async function listOwnerProducts(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "view_products");
  const rows = await repo.listOwnerProducts(ownerUserId);
  return repo.hydrateOwnerProducts(rows);
}

/**
 * يسرد عروض المتجر بعد التأكد من وجود merchant مرتبط بالحساب.
 */
export async function listOwnerOffers(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_offers");
  const rows = await offersRepo.listOwnerOffers(ownerUserId);
  return rows.map(mapOffer);
}

/**
 * ينشئ عرض متجر جديداً بعد التحقق من المنتجات المستهدفة وتوحيد productIds.
 *
 * التشخيص: إذا ظهر `PRODUCTS_NOT_FOUND` مع وجود المنتجات فعلياً افحص ملكية
 * هذه المنتجات للمتجر نفسه، لا مجرد وجودها العام في القاعدة.
 */
export async function createOwnerOffer(ownerUserId, dto) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_offers");
  const productIds = Array.isArray(dto.productIds)
    ? [...new Set(dto.productIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];
  const products = await offersRepo.listOwnerProductsByIds(ownerUserId, productIds);
  if (products.length !== productIds.length) {
    const err = new Error("PRODUCTS_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const created = await offersRepo.createOwnerOffer(ownerUserId, {
    title: dto.title.trim(),
    description: normalizeOptional(dto.description),
    offerType: dto.offerType,
    discountValue: dto.discountValue === undefined ? null : toNumberOrNull(dto.discountValue),
    buyQuantity: dto.buyQuantity === undefined ? null : toPositiveIntOrNull(dto.buyQuantity),
    getQuantity: dto.getQuantity === undefined ? null : toPositiveIntOrNull(dto.getQuantity),
    startsAt: dto.startsAt ? new Date(dto.startsAt).toISOString() : null,
    endsAt: dto.endsAt ? new Date(dto.endsAt).toISOString() : null,
    status: String(dto.status || "draft").trim().toLowerCase(),
    maxUsage: dto.maxUsage === undefined ? null : toPositiveIntOrNull(dto.maxUsage),
    productIds,
  });

  if (!created) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const full = await offersRepo.findOwnerOfferById(ownerUserId, created.id);
  const rows = await offersRepo.listOwnerOffers(ownerUserId);
  const target = rows.find((row) => Number(row.id) === Number(full?.id || created.id));
  return mapOffer(target || created);
}

/**
 * يحدّث العرض مع دعم تغيير المنتجات المرتبطة به والتحقق من سلامة القيم الرقمية.
 */
export async function updateOwnerOffer(ownerUserId, offerId, dto) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_offers");
  if (dto.productIds !== undefined) {
    const productIds = Array.isArray(dto.productIds)
      ? [...new Set(dto.productIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
      : [];
    const products = await offersRepo.listOwnerProductsByIds(ownerUserId, productIds);
    if (products.length !== productIds.length) {
      const err = new Error("PRODUCTS_NOT_FOUND");
      err.status = 404;
      throw err;
    }
  }

  const patch = {};
  if (dto.title !== undefined) patch.title = dto.title.trim();
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.offerType !== undefined) patch.offerType = dto.offerType;
  if (dto.discountValue !== undefined) patch.discountValue = toNumberOrNull(dto.discountValue);
  if (dto.buyQuantity !== undefined) patch.buyQuantity = toPositiveIntOrNull(dto.buyQuantity);
  if (dto.getQuantity !== undefined) patch.getQuantity = toPositiveIntOrNull(dto.getQuantity);
  if (dto.startsAt !== undefined) patch.startsAt = dto.startsAt ? new Date(dto.startsAt).toISOString() : null;
  if (dto.endsAt !== undefined) patch.endsAt = dto.endsAt ? new Date(dto.endsAt).toISOString() : null;
  if (dto.status !== undefined) patch.status = String(dto.status).trim().toLowerCase();
  if (dto.maxUsage !== undefined) patch.maxUsage = toPositiveIntOrNull(dto.maxUsage);
  if (dto.productIds !== undefined) {
    patch.productIds = [...new Set(dto.productIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))];
  }

  const updated = await offersRepo.updateOwnerOffer(ownerUserId, Number(offerId), patch);
  if (!updated) {
    const err = new Error("OFFER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const rows = await offersRepo.listOwnerOffers(ownerUserId);
  const target = rows.find((row) => Number(row.id) === Number(updated.id));
  return mapOffer(target || updated);
}

export async function deleteOwnerOffer(ownerUserId, offerId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_offers");
  const ok = await offersRepo.deleteOwnerOffer(ownerUserId, Number(offerId));
  if (!ok) {
    const err = new Error("OFFER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function listOwnerCategories(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "view_products");
  const rows = await repo.listOwnerCategories(ownerUserId);
  return rows.map(mapCategory);
}

/**
 * ينشئ تصنيفاً جديداً ويحوّل أخطاء unique constraint إلى code مفهوم للواجهة.
 */
export async function createOwnerCategory(ownerUserId, dto) {
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    ownerMerchant.id,
    "manage_store_profile"
  );
  const merchantActivityType = resolveMerchantActivityType(ownerMerchant);
  const resolvedCatalogType = normalizeCatalogType(
    dto.catalogType || inferCatalogTypeFromName(dto.name),
    "generic"
  );
  assertCategoryCatalogScope(
    merchantActivityType,
    resolvedCatalogType,
    "catalogType"
  );

  let created;
  try {
    created = await repo.createOwnerCategory(ownerUserId, {
      name: dto.name.trim(),
      sortOrder: Number(dto.sortOrder ?? 0),
      catalogType: resolvedCatalogType,
    });
  } catch (e) {
    if (e?.code === "23505" && String(e.constraint || "").includes("merchant_category_merchant_id_name")) {
      const err = new Error("CATEGORY_NAME_EXISTS");
      err.status = 409;
      throw err;
    }
    throw e;
  }

  if (!created) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(created.merchant_id);

  if (dto.publishGlobally === true) {
    const template = await upsertStoreActivityInternalTemplate({
      activityType: merchantActivityType,
      code: buildCatalogTemplateCode(dto.name, resolvedCatalogType),
      nameEn: dto.name.trim(),
      nameAr: dto.name.trim(),
      icon: null,
      orderIndex: Number(dto.sortOrder ?? 0),
      catalogType: resolvedCatalogType,
      isActive: true,
    });
    if (template?.id) {
      const appliedMerchantIds = await applyStoreActivityInternalTemplateToMerchants(
        template.id
      );
      await Promise.all(
        appliedMerchantIds.map((merchantId) =>
          invalidateMerchantCatalogCache(merchantId)
        )
      );
    }
  }

  return mapCategory(created);
}

export async function updateOwnerCategory(ownerUserId, categoryId, dto) {
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    ownerMerchant.id,
    "manage_store_profile"
  );
  const merchantActivityType = resolveMerchantActivityType(ownerMerchant);
  const patch = {};
  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);
  if (dto.catalogType !== undefined) {
    const nextCatalogType = normalizeCatalogType(dto.catalogType, null);
    assertCategoryCatalogScope(
      merchantActivityType,
      nextCatalogType,
      "catalogType"
    );
    patch.catalogType = nextCatalogType;
  }

  let updated;
  try {
    updated = await repo.updateOwnerCategory(ownerUserId, categoryId, patch);
  } catch (e) {
    if (e?.code === "23505" && String(e.constraint || "").includes("merchant_category_merchant_id_name")) {
      const err = new Error("CATEGORY_NAME_EXISTS");
      err.status = 409;
      throw err;
    }
    throw e;
  }
  if (!updated) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(updated.merchant_id);

  return mapCategory(updated);
}

export async function deleteOwnerCategory(ownerUserId, categoryId) {
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    ownerMerchant.id,
    "manage_store_profile"
  );
  const linkedProductsCount = await repo.countOwnerProductsByCategory(ownerUserId, categoryId);
  if (linkedProductsCount > 0) {
    const err = new Error("CATEGORY_HAS_PRODUCTS");
    err.status = 409;
    throw err;
  }

  const ok = await repo.deleteOwnerCategory(ownerUserId, categoryId);
  if (!ok) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(ownerMerchant.id);
}

/**
 * ينشئ منتجاً جديداً بعد التحقق من السعر والتخفيض ووجود التصنيف.
 */
export async function createOwnerProduct(ownerUserId, dto) {
  const price = toNumberOrNull(dto.price);
  const discountedPrice = toNumberOrNull(dto.discountedPrice);
  const categoryId = toPositiveIntOrNull(dto.categoryId);

  if (price === null) {
    const err = new Error("PRICE_INVALID");
    err.status = 400;
    throw err;
  }

  if (discountedPrice !== null && discountedPrice > price) {
    const err = new Error("DISCOUNT_PRICE_INVALID");
    err.status = 400;
    throw err;
  }

  if (categoryId === null) {
    const err = new Error("CATEGORY_REQUIRED");
    err.status = 400;
    throw err;
  }

  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, ownerMerchant.id, "create_products");
  const merchantActivityType = resolveMerchantActivityType(ownerMerchant);
  const category = await repo.findOwnerCategoryById(ownerUserId, categoryId);
  if (!category) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  assertCategoryCatalogScope(
    merchantActivityType,
    resolveCategoryCatalogType(category),
    "categoryId"
  );

  const richCatalog = hasRichProductInput(dto)
    ? normalizeRichProductPayload(dto)
    : null;
  const unavailableReason = normalizeOptional(dto.unavailableReason);
  const unavailableUntil = normalizeIsoDateOrNull(dto.unavailableUntil);
  const nextAvailability = snapshotAvailability({
    isAvailable: dto.isAvailable ?? true,
    unavailableReason,
    unavailableUntil,
  });
  if (snapshotsDiffer(snapshotAvailability(), nextAvailability)) {
    await ensureMerchantPermission(
      ownerUserId,
      ownerMerchant.id,
      "change_product_availability"
    );
  }

  const product = await repo.createOwnerProduct(ownerUserId, {
    name: dto.name.trim(),
    description: normalizeOptional(dto.description),
    categoryId,
    price,
    discountedPrice,
    imageUrl: normalizeOptional(dto.imageUrl),
    freeDelivery: dto.freeDelivery === true,
    offerLabel: normalizeOptional(dto.offerLabel),
    isAvailable: dto.isAvailable ?? true,
    unavailableReason,
    unavailableUntil,
    requiresPrescription: dto.requiresPrescription === true,
    requiresReview: dto.requiresReview === true,
    sortOrder: Number(dto.sortOrder ?? 0),
    stockQuantity:
      dto.stockQuantity === undefined || dto.stockQuantity === null || dto.stockQuantity === ""
        ? null
        : Math.max(0, Number(dto.stockQuantity)),
    richCatalog,
  });

  if (!product) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(product.merchant_id);

  await recordProductAvailabilityChange({
    actorUserId: ownerUserId,
    merchantId: product.merchant_id,
    productId: product.id,
    productName: product.name,
    beforeProduct: null,
    afterProduct: {
      isAvailable: product.is_available !== false,
      unavailableReason,
      unavailableUntil,
    },
    beforeRichCatalog: null,
    afterRichCatalog: richCatalog,
  });

  return product;
}

/**
 * يحدّث المنتج مع إعادة فحص علاقة السعر/التخفيض وملكية التصنيف عند الحاجة.
 */
export async function updateOwnerProduct(ownerUserId, productId, dto) {
  const patch = {};
  const richCatalog = hasRichProductInput(dto)
    ? normalizeRichProductPayload(dto)
    : null;
  const previousRichCatalog = richCatalog
    ? await loadProductRichCatalogById(productId)
    : null;
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  const merchantActivityType = resolveMerchantActivityType(ownerMerchant);
  const current = await repo.findMerchantProductById(ownerMerchant.id, productId);
  if (!current) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const requiresEditProducts =
    dto.name !== undefined ||
    dto.description !== undefined ||
    dto.imageUrl !== undefined ||
    dto.categoryId !== undefined ||
    dto.freeDelivery !== undefined ||
    dto.offerLabel !== undefined ||
    dto.requiresPrescription !== undefined ||
    dto.requiresReview !== undefined ||
    dto.sortOrder !== undefined ||
    dto.stockQuantity !== undefined ||
    dto.price !== undefined ||
    dto.discountedPrice !== undefined ||
    richCatalog !== null ||
    dto.attributes !== undefined ||
    dto.variantGroups !== undefined ||
    dto.variants !== undefined ||
    dto.media !== undefined;
  if (requiresEditProducts) {
    await ensureMerchantPermission(
      ownerUserId,
      ownerMerchant.id,
      "edit_products"
    );
  }
  if (productAvailabilityChanged(current, dto)) {
    await ensureMerchantPermission(
      ownerUserId,
      ownerMerchant.id,
      "change_product_availability"
    );
  }
  const effectiveCategoryId =
    dto.categoryId !== undefined
      ? toPositiveIntOrNull(dto.categoryId)
      : toPositiveIntOrNull(current.category_id);
  if (effectiveCategoryId === null) {
    const err = new Error("CATEGORY_REQUIRED");
    err.status = 400;
    throw err;
  }
  const category = await repo.findMerchantCategoryById(
    ownerMerchant.id,
    effectiveCategoryId
  );
  if (!category) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  assertCategoryCatalogScope(
    merchantActivityType,
    resolveCategoryCatalogType(category),
    "categoryId"
  );

  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.imageUrl !== undefined) patch.imageUrl = normalizeOptional(dto.imageUrl);
  if (dto.offerLabel !== undefined) patch.offerLabel = normalizeOptional(dto.offerLabel);
  if (dto.isAvailable !== undefined) patch.isAvailable = dto.isAvailable;
  if (dto.unavailableReason !== undefined) {
    patch.unavailableReason = normalizeOptional(dto.unavailableReason);
  }
  if (dto.unavailableUntil !== undefined) {
    patch.unavailableUntil = normalizeIsoDateOrNull(dto.unavailableUntil);
  }
  if (dto.freeDelivery !== undefined) patch.freeDelivery = dto.freeDelivery === true;
  if (dto.requiresPrescription !== undefined) {
    patch.requiresPrescription = dto.requiresPrescription === true;
  }
  if (dto.requiresReview !== undefined) {
    patch.requiresReview = dto.requiresReview === true;
  }
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);
  if (dto.stockQuantity !== undefined) {
    patch.stockQuantity = dto.stockQuantity === null || dto.stockQuantity === ""
      ? null
      : Math.max(0, Number(dto.stockQuantity));
  }
  if (richCatalog) patch.richCatalog = richCatalog;

  if (dto.categoryId !== undefined) {
    patch.categoryId = effectiveCategoryId;
  }

  if (dto.price !== undefined) {
    const p = toNumberOrNull(dto.price);
    if (p === null) {
      const err = new Error("PRICE_INVALID");
      err.status = 400;
      throw err;
    }
    patch.price = p;
  }

  if (dto.discountedPrice !== undefined) {
    const d = toNumberOrNull(dto.discountedPrice);
    patch.discountedPrice = d;
  }

  if (patch.price !== undefined || patch.discountedPrice !== undefined) {
    const basePrice = patch.price ?? Number(current.price);
    const nextDiscount = patch.discountedPrice ?? (current.discounted_price === null ? null : Number(current.discounted_price));
    if (nextDiscount !== null && nextDiscount > basePrice) {
      const err = new Error("DISCOUNT_PRICE_INVALID");
      err.status = 400;
      throw err;
    }
  }

  const updated = await repo.updateOwnerProduct(
    ownerUserId,
    ownerMerchant.id,
    productId,
    patch
  );
  if (!updated) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await recordProductAvailabilityChange({
    actorUserId: ownerUserId,
    merchantId: updated.merchant_id,
    productId: updated.id,
    productName: updated.name,
    beforeProduct: current,
    afterProduct: updated,
    beforeRichCatalog: previousRichCatalog,
    afterRichCatalog: richCatalog,
  });
  await invalidateMerchantCatalogCache(updated.merchant_id);
  return updated;
}

export async function deleteOwnerProduct(ownerUserId, productId) {
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, ownerMerchant.id, "delete_products");
  const ok = await repo.deleteOwnerProduct(ownerUserId, productId);
  if (!ok) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(ownerMerchant.id);
}

export async function listDeliveryAgents(ownerUserId) {
  await getOwnerMerchant(ownerUserId);
  const rows = await repo.listOwnerDeliveryAgents(ownerUserId);
  return rows.map(mapDeliveryAgent);
}

export async function listAccountants(ownerUserId) {
  const rows = await repo.listOwnerAccountants(ownerUserId);
  return rows.map(mapAccountant);
}

export async function listHrStaff(ownerUserId) {
  const rows = await repo.listOwnerHrStaff(ownerUserId);
  return rows.map(mapHrStaff);
}

export async function searchStaffUsers(ownerUserId, { search = "", limit = 100 } = {}) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const rows = await repo.searchUsersForStaff(ownerUserId, { search, limit });
  return rows.map(mapStaffSearchUser);
}

/**
 * ينشئ حساب delivery جديداً ويربطه بالمتجر كسائق متجر مع اعتماد الحساب فوراً.
 *
 * Side effects:
 * - إنشاء app_user
 * - اعتماد حساب delivery
 * - ربط affiliation في commerce
 */
export async function createDeliveryAgent(ownerUserId, dto) {
  const ownerUser = await getUserPublicById(Number(ownerUserId));
  if (!ownerUser) {
    const err = new Error("OWNER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || "").trim();
  if (!fullName) {
    const err = new Error("FULL_NAME_REQUIRED");
    err.status = 400;
    throw err;
  }
  if (!/^\d{8,20}$/.test(phone)) {
    const err = new Error("PHONE_INVALID");
    err.status = 400;
    throw err;
  }
  if (!/^\d{4,8}$/.test(pin)) {
    const err = new Error("PIN_INVALID");
    err.status = 400;
    throw err;
  }

  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(pin);
  const created = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: ownerUser.block || "A",
        buildingNumber: ownerUser.building_number || "A101",
        apartment: ownerUser.apartment || "101",
        imageUrl: normalizeOptional(dto.imageUrl),
        role: "delivery",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "owner_created_delivery_v1",
        analyticsConsentGrantedAt: new Date(),
        chatQualityReviewConsent: true,
      }),
  });

  await ordersRepo.ensureDeliveryAccountApproved(Number(created.id));
  await commerceRepo.syncCourierDriverAffiliation({
    userId: Number(created.id),
    driverType: "store_driver",
    merchantId: Number(merchant.id),
    merchantIdSet: true,
    actorUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(created.id),
      fullName: created.full_name,
      phone: created.phone,
        role: created.role,
        isTaxiCaptain: false,
        deliveryAccountApproved: true,
        driverType: "store_driver",
        merchantId: Number(merchant.id),
        merchantName: merchant.name,
      },
  };
}

/**
 * يعيد استخدام حساب موجود ويربطه بالمتجر كسائق delivery بعد فحص الأهلية.
 */
export async function assignExistingDeliveryAgent(ownerUserId, userId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const candidate = await repo.findUserForStaffById(Number(userId));
  assertValidStaffCandidate(candidate, { targetRole: "delivery" });

  let updated = candidate;
  if (String(candidate.role || "").toLowerCase() !== "delivery") {
    updated = await repo.setUserRole(Number(candidate.id), "delivery");
  }

  await ordersRepo.ensureDeliveryAccountApproved(Number(candidate.id));
  await commerceRepo.syncCourierDriverAffiliation({
    userId: Number(candidate.id),
    driverType: "store_driver",
    merchantId: Number(merchant.id),
    merchantIdSet: true,
    actorUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(candidate.id),
      fullName: updated?.full_name || candidate.full_name,
      phone: updated?.phone || candidate.phone,
        role: "delivery",
        isTaxiCaptain: false,
        deliveryAccountApproved: true,
        driverType: "store_driver",
        merchantId: Number(merchant.id),
        merchantName: merchant.name,
      },
  };
}

/**
 * ينشئ محاسباً جديداً ويربطه بالمتجر.
 */
export async function createAccountant(ownerUserId, dto) {
  const ownerUser = await getUserPublicById(Number(ownerUserId));
  if (!ownerUser) {
    const err = new Error("OWNER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || "").trim();
  if (!fullName) {
    const err = new Error("FULL_NAME_REQUIRED");
    err.status = 400;
    throw err;
  }
  if (!/^\d{8,20}$/.test(phone)) {
    const err = new Error("PHONE_INVALID");
    err.status = 400;
    throw err;
  }
  if (!/^\d{4,8}$/.test(pin)) {
    const err = new Error("PIN_INVALID");
    err.status = 400;
    throw err;
  }

  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(pin);
  const created = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: ownerUser.block || "A",
        buildingNumber: ownerUser.building_number || "A101",
        apartment: ownerUser.apartment || "101",
        imageUrl: normalizeOptional(dto.imageUrl),
        role: "accountant",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "owner_created_accountant_v1",
        analyticsConsentGrantedAt: new Date(),
        chatQualityReviewConsent: true,
      }),
  });

  await repo.linkAccountantToMerchant({
    merchantId: Number(merchant.id),
    accountantUserId: Number(created.id),
    createdByUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(created.id),
      fullName: created.full_name,
      phone: created.phone,
      role: created.role,
      merchantId: Number(merchant.id),
      merchantName: merchant.name,
    },
  };
}

/**
 * يربط حساباً موجوداً بالمتجر كـ accountant بعد تعديل الدور عند الحاجة.
 */
export async function assignExistingAccountant(ownerUserId, userId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const candidate = await repo.findUserForStaffById(Number(userId));
  assertValidStaffCandidate(candidate, { targetRole: "accountant" });

  let updated = candidate;
  if (String(candidate.role || "").toLowerCase() !== "accountant") {
    updated = await repo.setUserRole(Number(candidate.id), "accountant");
  }

  await repo.linkAccountantToMerchant({
    merchantId: Number(merchant.id),
    accountantUserId: Number(candidate.id),
    createdByUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(candidate.id),
      fullName: updated?.full_name || candidate.full_name,
      phone: updated?.phone || candidate.phone,
      role: "accountant",
      merchantId: Number(merchant.id),
      merchantName: merchant.name,
    },
  };
}

/**
 * ينشئ موظف HR جديداً ويربطه بالمتجر.
 */
export async function createHrStaff(ownerUserId, dto) {
  const ownerUser = await getUserPublicById(Number(ownerUserId));
  if (!ownerUser) {
    const err = new Error("OWNER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || "").trim();
  if (!fullName) {
    const err = new Error("FULL_NAME_REQUIRED");
    err.status = 400;
    throw err;
  }
  if (!/^\d{8,20}$/.test(phone)) {
    const err = new Error("PHONE_INVALID");
    err.status = 400;
    throw err;
  }
  if (!/^\d{4,8}$/.test(pin)) {
    const err = new Error("PIN_INVALID");
    err.status = 400;
    throw err;
  }

  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(pin);
  const created = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: ownerUser.block || "A",
        buildingNumber: ownerUser.building_number || "A101",
        apartment: ownerUser.apartment || "101",
        imageUrl: normalizeOptional(dto.imageUrl),
        role: "hr",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "owner_created_hr_v1",
        analyticsConsentGrantedAt: new Date(),
        chatQualityReviewConsent: true,
      }),
  });

  await repo.linkHrToMerchant({
    merchantId: Number(merchant.id),
    hrUserId: Number(created.id),
    createdByUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(created.id),
      fullName: created.full_name,
      phone: created.phone,
      role: created.role,
      merchantId: Number(merchant.id),
      merchantName: merchant.name,
    },
  };
}

/**
 * يربط حساباً موجوداً بالمتجر كموظف HR بعد اجتياز checks الأهلية.
 */
export async function assignExistingHrStaff(ownerUserId, userId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "manage_employees");
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const candidate = await repo.findUserForStaffById(Number(userId));
  assertValidStaffCandidate(candidate, { targetRole: "hr" });

  let updated = candidate;
  if (String(candidate.role || "").toLowerCase() !== "hr") {
    updated = await repo.setUserRole(Number(candidate.id), "hr");
  }

  await repo.linkHrToMerchant({
    merchantId: Number(merchant.id),
    hrUserId: Number(candidate.id),
    createdByUserId: Number(ownerUserId),
    source: "owner",
  });

  return {
    user: {
      id: Number(candidate.id),
      fullName: updated?.full_name || candidate.full_name,
      phone: updated?.phone || candidate.phone,
      role: "hr",
      merchantId: Number(merchant.id),
      merchantName: merchant.name,
    },
  };
}

export async function listCurrentOrders(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "view_orders");
  return ordersRepo.listOwnerCurrentOrders(ownerUserId);
}

export async function listOrderHistory(ownerUserId, archiveDate) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "view_orders");
  return ordersRepo.listOwnerOrderHistory(ownerUserId, archiveDate || null);
}

/**
 * يمرر انتقال حالة الطلب من owner إلى orders repo.
 *
 * Maintenance notes:
 * - إذا بدا أن الحالة لم تتغير رغم نجاح 204 افحص `ordersRepo.updateOwnerOrderStatus`
 *   ثم القيود الخاصة بالحالة الحالية للطلب.
 */
export async function updateOrderStatus(
  ownerUserId,
  orderId,
  status,
  estimatedPrepMinutes,
  estimatedDeliveryMinutes
) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantAnyPermission(
    ownerUserId,
    merchant.id,
    requiredOrderStatusPermissions(status)
  );
  const updated = await ordersRepo.updateOwnerOrderStatus(
    ownerUserId,
    Number(orderId),
    status,
    estimatedPrepMinutes === undefined ? null : Number(estimatedPrepMinutes),
    estimatedDeliveryMinutes === undefined ? null : Number(estimatedDeliveryMinutes)
  );
  if (!updated) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

/**
 * يسند الطلب إلى delivery user أو إلى نمط assignment محدد.
 */
export async function assignDelivery(
  ownerUserId,
  orderId,
  deliveryUserId,
  assignmentMode = "platform_delivery"
) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "assign_delivery");
  const updated = await ordersRepo.assignDeliveryToOwnerOrder(
    merchant.id,
    Number(orderId),
    deliveryUserId == null ? null : Number(deliveryUserId),
    { assignmentMode }
  );
  if (!updated) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

/**
 * يعلّم عنصر طلب واحداً كغير متوفر ويرولد إشعاراً للعميل المتأثر.
 */
export async function markOrderItemUnavailable(
  ownerUserId,
  orderId,
  productId,
  dto = {}
) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "prepare_orders");
  await ensureMerchantPermission(
    ownerUserId,
    merchant.id,
    "mark_order_item_unavailable"
  );
  const nextUnavailableReason =
    normalizeOptional(dto.unavailableReason) || "ORDER_PREPARATION_UNAVAILABLE";
  const nextUnavailableUntil = normalizeIsoDateOrNull(dto.unavailableUntil);
  const target = await repo.markOrderedProductUnavailable(
    ownerUserId,
    Number(orderId),
    Number(productId),
    dto
  );

  if (!target) {
    const err = new Error("ORDER_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  try {
    await insertAvailabilityAuditLog({
      merchantId: target.merchant_id,
      productId: Number(target.product_id),
      actorUserId: ownerUserId,
      actorRole: "owner",
      actionKey: "owner.order_item.marked_unavailable",
      summary: `Marked ${target.product_name || "product"} unavailable while preparing order #${target.order_id}`,
      oldValue: {
        isAvailable: target.previous_is_available !== false,
        unavailableReason: normalizeOptional(target.previous_unavailable_reason),
        unavailableUntil: normalizeIsoDateOrNull(target.previous_unavailable_until),
      },
      newValue: {
        isAvailable: false,
        unavailableReason: nextUnavailableReason,
        unavailableUntil: nextUnavailableUntil,
      },
      reason: nextUnavailableReason,
      unavailableUntil: nextUnavailableUntil,
    });
  } catch (error) {
    console.error("ORDER_ITEM_UNAVAILABLE_AUDIT_LOG_FAILED", error);
  }

  await createNotification({
    userId: target.customer_user_id,
    type: "customer_order_item_unavailable",
    title: "مادة غير متوفرة",
    body: `المادة ${target.product_name} التي طلبتها من ${target.merchant_name} غير متوفرة الآن. اختر بديلاً آخر إذا رغبت.`,
    orderId: Number(target.order_id),
    merchantId: Number(target.merchant_id),
    payload: {
      orderId: Number(target.order_id),
      productId: Number(target.product_id),
      productName: target.product_name,
      merchantName: target.merchant_name,
      target: "order_tracking",
    },
  });
  await invalidateMerchantCatalogCache(target.merchant_id);

  return repo.findOwnerProductById(ownerUserId, Number(productId));
}

export const __ownerServiceTestables = Object.freeze({
  normalizeIsoDateOrNull,
  snapshotAvailability,
  snapshotsDiffer,
  buildAvailabilityAuditValue,
  availabilityKey,
  requiredOrderStatusPermissions,
  productAvailabilityChanged,
});

export async function ownerAnalytics(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(ownerUserId, merchant.id, "view_reports");
  return analyticsRepo.getOwnerAnalytics(ownerUserId);
}

export async function printOrdersReport(ownerUserId, period) {
  const normalizedPeriod = String(period || "day").trim().toLowerCase();
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    merchant.id,
    "view_financial_reports"
  );
  return ordersRepo.listOwnerOrdersForReport(ownerUserId, normalizedPeriod);
}

/**
 * يعيد ملخص المستحقات المفتوحة لصاحب المتجر.
 */
export async function settlementSummary(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    merchant.id,
    "view_financial_reports"
  );
  return analyticsRepo.getOwnerOutstanding(ownerUserId);
}

/**
 * Store-side view of the merchant's own monthly subscription debt. Requires the
 * financial-reports permission so store employees without financial access
 * (and disabled employees) cannot see subscription financials. Read-only and
 * strictly scoped to the caller's merchant. Kept separate from per-order cash
 * settlement (settlementSummary above).
 */
export async function monthlySubscriptionSummary(ownerUserId) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    merchant.id,
    "view_financial_reports"
  );
  const profile = await getMerchantBillingProfile(merchant.id);
  return subscriptionsService.getMerchantSubscriptionSummary(merchant.id, {
    billingModel: profile.commissionModel,
  });
}

/**
 * ينشئ طلب تسوية مالية جديداً إذا كان المتجر موجوداً.
 */
export async function requestSettlement(ownerUserId, note) {
  const merchant = await getOwnerMerchant(ownerUserId);
  await ensureMerchantPermission(
    ownerUserId,
    merchant.id,
    "view_financial_reports"
  );
  const out = await analyticsRepo.createOwnerSettlementRequest(
    ownerUserId,
    note?.trim()
  );
  if (!out) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}
