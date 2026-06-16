import { hashPin } from "../../shared/utils/hash.js";
import { markSessionRevoked } from "../../shared/middleware/access-auth.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import { createUser, findUserByPhone, getUserPublicById } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import { createUserSession, pruneUserSessions } from "../auth/auth.repo.js";
import * as analyticsRepo from "../../shared/analytics/commerce-analytics.repo.js";
import * as commerceRepo from "../commerce/commerce.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import { invalidateOrderListCacheForUser } from "../orders/orders.service.js";
import * as offersRepo from "./merchant-offers.repo.js";
import * as repo from "./owner.repo.js";
import { env } from "../../config/env.js";
import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";
import { createNotification } from "../notifications/notifications.repo.js";
import {
  buildMerchantOfferLabel,
  computeMerchantOfferState,
} from "./merchant-offers.logic.js";
import { invalidateMerchantCatalogCache } from "../merchants/merchants.repo.js";
import crypto from "crypto";
import {
  buildMerchantCapabilities,
  inferActivityTypeFromMerchantType,
  normalizeActivityType,
  normalizeDiscoverySubcategoryList,
  requireActivityConfig,
  requireValidDiscoverySelection,
} from "../merchants/store-activity.registry.js";

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
function mapMerchant(m) {
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
    sortOrder: c.sort_order,
    createdAt: c.created_at,
    updatedAt: c.updated_at,
  };
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
  const refreshToken = crypto.randomBytes(24).toString("base64url");
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
    sessionId: session?.id || null,
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
export async function registerOwner(dto, deviceContext = {}) {
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const address = resolveOwnerAddress(dto);
  const requestedActivityType = normalizeActivityType(
    dto.merchantActivityType,
    inferActivityTypeFromMerchantType(dto.merchantType)
  );
  const activityConfig = await requireActivityConfig(requestedActivityType);
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

  const session = await issueOwnerSession(out.user, deviceContext);

  return {
    token: session.token,
    sessionId: session.sessionId,
    user: mapUser(out.user),
    merchant: mapMerchant(out.merchant),
  };
}

/**
 * يعيد المتجر المرتبط بصاحب المتجر الحالي أو يرمي `MERCHANT_NOT_FOUND`.
 */
export async function getOwnerMerchant(ownerUserId) {
  const merchant = await repo.findMerchantByOwnerUserId(ownerUserId);
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
export async function updateOwnerMerchant(ownerUserId, dto) {
  const currentMerchant = await repo.findMerchantByOwnerUserId(ownerUserId);
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
  return repo.listOwnerProducts(ownerUserId);
}

/**
 * يسرد عروض المتجر بعد التأكد من وجود merchant مرتبط بالحساب.
 */
export async function listOwnerOffers(ownerUserId) {
  await getOwnerMerchant(ownerUserId);
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
  await getOwnerMerchant(ownerUserId);
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
  await getOwnerMerchant(ownerUserId);
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
  const ok = await offersRepo.deleteOwnerOffer(ownerUserId, Number(offerId));
  if (!ok) {
    const err = new Error("OFFER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function listOwnerCategories(ownerUserId) {
  const rows = await repo.listOwnerCategories(ownerUserId);
  return rows.map(mapCategory);
}

/**
 * ينشئ تصنيفاً جديداً ويحوّل أخطاء unique constraint إلى code مفهوم للواجهة.
 */
export async function createOwnerCategory(ownerUserId, dto) {
  let created;
  try {
    created = await repo.createOwnerCategory(ownerUserId, {
      name: dto.name.trim(),
      sortOrder: Number(dto.sortOrder ?? 0),
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

  return mapCategory(created);
}

export async function updateOwnerCategory(ownerUserId, categoryId, dto) {
  const patch = {};
  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);

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

  const category = await repo.findOwnerCategoryById(ownerUserId, categoryId);
  if (!category) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
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
    requiresPrescription: dto.requiresPrescription === true,
    requiresReview: dto.requiresReview === true,
    sortOrder: Number(dto.sortOrder ?? 0),
  });

  if (!product) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(product.merchant_id);

  return product;
}

/**
 * يحدّث المنتج مع إعادة فحص علاقة السعر/التخفيض وملكية التصنيف عند الحاجة.
 */
export async function updateOwnerProduct(ownerUserId, productId, dto) {
  const patch = {};

  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.imageUrl !== undefined) patch.imageUrl = normalizeOptional(dto.imageUrl);
  if (dto.offerLabel !== undefined) patch.offerLabel = normalizeOptional(dto.offerLabel);
  if (dto.isAvailable !== undefined) patch.isAvailable = dto.isAvailable;
  if (dto.freeDelivery !== undefined) patch.freeDelivery = dto.freeDelivery === true;
  if (dto.requiresPrescription !== undefined) {
    patch.requiresPrescription = dto.requiresPrescription === true;
  }
  if (dto.requiresReview !== undefined) {
    patch.requiresReview = dto.requiresReview === true;
  }
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);

  if (dto.categoryId !== undefined) {
    const categoryId = toPositiveIntOrNull(dto.categoryId);
    if (categoryId === null) {
      const err = new Error("CATEGORY_REQUIRED");
      err.status = 400;
      throw err;
    }
    const category = await repo.findOwnerCategoryById(ownerUserId, categoryId);
    if (!category) {
      const err = new Error("CATEGORY_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    patch.categoryId = categoryId;
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
    const current = await repo.findOwnerProductById(ownerUserId, productId);
    if (!current) {
      const err = new Error("PRODUCT_NOT_FOUND");
      err.status = 404;
      throw err;
    }

    const basePrice = patch.price ?? Number(current.price);
    const nextDiscount = patch.discountedPrice ?? (current.discounted_price === null ? null : Number(current.discounted_price));
    if (nextDiscount !== null && nextDiscount > basePrice) {
      const err = new Error("DISCOUNT_PRICE_INVALID");
      err.status = 400;
      throw err;
    }
  }

  const updated = await repo.updateOwnerProduct(ownerUserId, productId, patch);
  if (!updated) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await invalidateMerchantCatalogCache(updated.merchant_id);
  return updated;
}

export async function deleteOwnerProduct(ownerUserId, productId) {
  const ownerMerchant = await getOwnerMerchant(ownerUserId);
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
  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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

  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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
  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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

  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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
  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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

  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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
  const merchant = await repo.findMerchantByOwnerUserId(Number(ownerUserId));
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
  return ordersRepo.listOwnerCurrentOrders(ownerUserId);
}

export async function listOrderHistory(ownerUserId, archiveDate) {
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
  const updated = await ordersRepo.assignDeliveryToOwnerOrder(
    ownerUserId,
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
export async function markOrderItemUnavailable(ownerUserId, orderId, productId) {
  const target = await repo.markOrderedProductUnavailable(
    ownerUserId,
    Number(orderId),
    Number(productId)
  );

  if (!target) {
    const err = new Error("ORDER_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
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

export async function ownerAnalytics(ownerUserId) {
  return analyticsRepo.getOwnerAnalytics(ownerUserId);
}

export async function printOrdersReport(ownerUserId, period) {
  const normalizedPeriod = String(period || "day").toLowerCase();
  return ordersRepo.listOwnerOrdersForReport(ownerUserId, normalizedPeriod);
}

/**
 * يعيد ملخص المستحقات المفتوحة لصاحب المتجر.
 */
export async function settlementSummary(ownerUserId) {
  return analyticsRepo.getOwnerOutstanding(ownerUserId);
}

/**
 * ينشئ طلب تسوية مالية جديداً إذا كان المتجر موجوداً.
 */
export async function requestSettlement(ownerUserId, note) {
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
