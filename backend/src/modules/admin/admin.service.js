import { hashPin } from "../../shared/utils/hash.js";
import {
  invalidateSessionAccessCacheForUser,
  markUserSessionsRevokedAfter,
} from "../../shared/middleware/access-auth.js";
import {
  createUser,
  findUserByPhone,
  revokeAllUserSessions,
} from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import * as analyticsRepo from "../../shared/analytics/commerce-analytics.repo.js";
import * as behaviorService from "../behavior/behavior.service.js";
import * as commerceRepo from "../commerce/commerce.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import * as taxiService from "../taxi/taxi.service.js";
import * as adminRepo from "./admin.repo.js";
import {
  listActivityRegistry,
  requireActivityConfig,
  requireValidDiscoverySelection,
} from "../merchants/store-activity.registry.js";
import { resolveStoreDepartmentForWrite } from "../merchants/store-department.logic.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { env } from "../../config/env.js";

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function toIsoOrNull(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function toActorUserId(actor = {}) {
  return Number(actor.userId || actor.id || 0) || 0;
}

function toActorRole(actor = {}) {
  const role = String(actor.userRole || actor.role || "").trim();
  return role || null;
}

function isSchemaCompatibilityError(error) {
  const code = String(error?.code || "").trim().toUpperCase();
  if (code === "42P01" || code === "42703" || code === "42883") return true;
  return false;
}

async function logAdminAudit({
  actor,
  actionKey,
  summary,
  targetType = null,
  targetId = null,
  targetLabel = null,
  metadata = null,
}) {
  const actorUserId = toActorUserId(actor);
  if (actorUserId <= 0) return;
  await adminRepo.insertAdminAuditEvent({
    actorUserId,
    actorRole: toActorRole(actor),
    actionKey,
    summary,
    targetType,
    targetId,
    targetLabel,
    metadata,
  });
}

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

function mapSocialModerationUser(row) {
  return {
    id: Number(row.id),
    username: row.username || null,
    fullName: row.full_name || null,
    phone: row.phone || null,
    role: row.role || null,
    imageUrl: row.image_url || null,
    block: row.block || null,
    buildingNumber: row.building_number || null,
    apartment: row.apartment || null,
    isSuperAdmin: row.is_super_admin === true,
    isAccountDisabled: row.is_account_disabled === true,
    accountDisabledNote: row.account_disabled_note || null,
    accountDisabledAt: toIsoOrNull(row.account_disabled_at),
    accountEnabledAt: toIsoOrNull(row.account_enabled_at),
    createdAt: toIsoOrNull(row.created_at),
    updatedAt: toIsoOrNull(row.updated_at),
  };
}

function normalizeDriverType(value, fallback = "app_driver") {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "store_driver") return "store_driver";
  if (normalized === "app_driver") return "app_driver";
  return fallback;
}

export async function createManagedUser(dto, actor = {}) {
  const requesterId = toActorUserId(actor);
  const requesterIsSuperAdmin =
    actor.isSuperAdmin === true ||
    (requesterId > 0 && (await adminRepo.isUserSuperAdmin(requesterId)));

  const role = String(dto.role || "").trim();
  if (role === "admin" && !requesterIsSuperAdmin) {
    const err = new Error("FORBIDDEN_SUPER_ADMIN_ONLY");
    err.status = 403;
    throw err;
  }

  let merchant = null;
  let staffMerchantId = null;
  const requestedDriverType =
    role === "delivery" ? normalizeDriverType(dto.driverType, "app_driver") : null;
  const requiresMerchant =
    role === "accountant" ||
    role === "hr" ||
    (role === "delivery" && requestedDriverType === "store_driver");

  if (requiresMerchant) {
    const parsedMerchantId = Number(dto.merchantId);
    if (!Number.isInteger(parsedMerchantId) || parsedMerchantId <= 0) {
      const err = new Error("STAFF_MERCHANT_REQUIRED");
      err.status = 400;
      throw err;
    }
    merchant = await adminRepo.getMerchantById(parsedMerchantId);
    if (!merchant) {
      const err = new Error("MERCHANT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    staffMerchantId = parsedMerchantId;
  }

  if (role === "delivery" && !requiresMerchant) {
    const parsedMerchantId =
      dto.merchantId === undefined || dto.merchantId === null || dto.merchantId === ""
        ? null
        : Number(dto.merchantId);
    if (parsedMerchantId != null) {
      merchant = await adminRepo.getMerchantById(parsedMerchantId);
      if (!merchant) {
        const err = new Error("MERCHANT_NOT_FOUND");
        err.status = 404;
        throw err;
      }
      staffMerchantId = parsedMerchantId;
    }
  }

  const exists = await findUserByPhone(dto.phone.trim());
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const fullName = dto.fullName.trim();
  const phone = dto.phone.trim();
  const pinHash = await hashPin(dto.pin);
  const user = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: dto.block.trim(),
        buildingNumber: dto.buildingNumber.trim(),
        apartment: dto.apartment.trim(),
        imageUrl: dto.imageUrl || null,
        role,
        analyticsConsentGranted: true,
        analyticsConsentVersion: "admin_created_v1",
        analyticsConsentGrantedAt: new Date(),
      }),
  });

  if (role === "delivery") {
    await ordersRepo.ensureDeliveryAccountApproved(Number(user.id));
    await commerceRepo.syncCourierDriverAffiliation({
      userId: Number(user.id),
      driverType: requestedDriverType,
      merchantId: staffMerchantId,
      merchantIdSet: true,
      actorUserId: requesterId,
      source: "admin",
    });
  }

  if (role === "accountant" && staffMerchantId) {
    await adminRepo.linkAccountantToMerchant({
      merchantId: Number(staffMerchantId),
      accountantUserId: Number(user.id),
      createdByUserId: requesterId,
      source: "admin",
    });
  }

  if (role === "hr" && staffMerchantId) {
    await adminRepo.linkHrToMerchant({
      merchantId: Number(staffMerchantId),
      hrUserId: Number(user.id),
      createdByUserId: requesterId,
      source: "admin",
    });
  }

  await logAdminAudit({
    actor,
    actionKey: "admin.user.created",
    summary: `Created managed user ${user.full_name}`,
    targetType: "user",
    targetId: user.id,
    targetLabel: user.full_name,
    metadata: {
      role: user.role,
      phone: user.phone,
      block: user.block,
      buildingNumber: user.building_number,
      apartment: user.apartment,
      merchantId: staffMerchantId,
      merchantName: merchant?.name || null,
      driverType: requestedDriverType,
    },
  });

  return {
    ...mapUser(user),
    merchantId: staffMerchantId,
    merchantName: merchant?.name || null,
    driverType: requestedDriverType,
  };
}

export async function listAvailableOwners() {
  const rows = await adminRepo.listAvailableOwnerAccounts();
  return rows.map((u) => ({
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
  }));
}

export async function getAnalytics() {
  return analyticsRepo.getAdminAnalytics();
}

export async function getPendingMerchants() {
  return analyticsRepo.listPendingMerchants();
}

export async function approveMerchant(merchantId, adminUserId, body = {}) {
  const out = await commerceRepo.submitMerchantFinancialTermsForApproval({
    adminUserId: toActorUserId(adminUserId),
    merchantId: Number(merchantId),
    patch: body || {},
  });

  const merchant = await adminRepo.getMerchantById(Number(merchantId));
  if (out.merchant?.owner_user_id) {
    await createManyNotifications([
      {
        userId: Number(out.merchant.owner_user_id),
        type: "owner_financial_terms_pending_acceptance",
        title: "الشروط المالية بانتظار موافقة المتجر",
        body:
          "راجِع الشروط المالية الخاصة بمتجر " +
          out.merchant.name +
          " ووافق عليها لتفعيل الحساب.",
        merchantId: Number(out.merchant.id),
        payload: {
          merchantId: Number(out.merchant.id),
          approvalStatus: "awaiting_store_financial_acceptance",
          target: "owner_financial_terms",
          targetModule: "merchant",
          roleScope: "owner",
          action: "review_financial_terms",
        },
      },
    ]);
  }

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.merchant.financial_terms_sent",
    summary:
      "أرسل الشروط المالية إلى المتجر " + (merchant?.name || `#${merchantId}`),
    targetType: "merchant",
    targetId: Number(merchantId),
    targetLabel: merchant?.name || null,
    metadata: {
      merchantType: merchant?.type || null,
      isDisabled: merchant?.is_disabled === true,
      approvalStatus: out.merchant?.approval_status || null,
      financialTerms: out.financialTerms || null,
    },
  });
}

export async function getPendingSettlements() {
  return analyticsRepo.listPendingSettlements();
}

export async function approveSettlement(settlementId, adminUserId, adminNote) {
  const ok = await analyticsRepo.approveSettlement(
    Number(settlementId),
    toActorUserId(adminUserId),
    adminNote?.trim()
  );
  if (!ok) {
    const err = new Error("SETTLEMENT_NOT_FOUND_OR_ALREADY_PROCESSED");
    err.status = 404;
    throw err;
  }

  const settlement = await adminRepo.getSettlementById(Number(settlementId));
  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.settlement.approved",
    summary:
      `صادق على تسوية ${settlement?.merchant_name || `#${settlementId}`}` +
      (settlement?.amount != null ? ` بقيمة ${Number(settlement.amount).toFixed(0)} د.ع` : ""),
    targetType: "settlement",
    targetId: Number(settlementId),
    targetLabel: settlement?.merchant_name || null,
    metadata: {
      merchantId: settlement?.merchant_id || null,
      ownerUserId: settlement?.owner_user_id || null,
      adminNote: adminNote?.trim() || null,
      amount: settlement?.amount != null ? Number(settlement.amount) : null,
    },
  });
}

function mapManagedMerchant(m) {
  return {
    id: m.id,
    name: m.name,
    type: m.type,
    activityType: m.activity_type || null,
    storeDepartment: m.store_department || null,
    discoverySubcategory: m.discovery_subcategory || null,
    discoverySelectAll: m.discovery_select_all === true,
    phone: m.phone,
    description: m.description || null,
    isOpen: m.is_open,
    isApproved: m.is_approved,
    isDisabled: m.is_disabled,
    ownerUserId: m.owner_user_id,
    ownerFullName: m.owner_full_name,
    ownerPhone: m.owner_phone,
    todayOrdersCount: Number(m.today_orders_count || 0),
    createdAt: m.created_at,
  };
}

export async function listMerchants() {
  const rows = await adminRepo.listManagedMerchants();
  return rows.map(mapManagedMerchant);
}

function mapStoreActivity(row = {}) {
  return {
    activityType: row.activity_type || row.activityType || null,
    baseType: row.base_type || row.baseType || "market",
    displayNameEn: row.display_name_en || row.displayNameEn || "",
    displayNameAr: row.display_name_ar || row.displayNameAr || "",
    hasDiscoverySubcategories:
      row.has_discovery_subcategories === true ||
      row.hasDiscoverySubcategories === true,
    supportsChat: row.supports_chat === true || row.supportsChat === true,
    supportsAttachments:
      row.supports_attachments === true || row.supportsAttachments === true,
    supportsPharmacyWorkflow:
      row.supports_pharmacy_workflow === true ||
      row.supportsPharmacyWorkflow === true,
    internalCategoryMode:
      row.internal_category_mode ||
      row.internalCategoryMode ||
      "merchant_defined_with_templates",
    isActive: row.is_active !== false && row.isActive !== false,
  };
}

export async function listStoreActivitiesForAdmin() {
  const rows = await listActivityRegistry({ includeInactive: true });
  return { items: rows.map(mapStoreActivity) };
}

export async function upsertStoreActivityForAdmin(payload, actor = {}) {
  const row = await adminRepo.upsertStoreActivityDefinition(payload);
  await logAdminAudit({
    actor,
    actionKey: "admin.store_activity.upserted",
    summary: `Store activity ${payload.activityType} saved by admin`,
    targetType: "store_activity_definition",
    targetId: null,
    targetLabel: payload.activityType,
    metadata: {
      activityType: payload.activityType,
      baseType: payload.baseType,
      displayNameAr: payload.displayNameAr,
      displayNameEn: payload.displayNameEn,
      isActive: payload.isActive !== false,
    },
  });
  return { item: mapStoreActivity(row) };
}

export async function updateManagedMerchantProfile(merchantId, patch, actor = {}) {
  const safeMerchantId = Number(merchantId);
  if (!Number.isInteger(safeMerchantId) || safeMerchantId <= 0) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const current = await adminRepo.getMerchantById(safeMerchantId);
  if (!current) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const nextActivityType = patch.activityType || current.activity_type;
  const activityConfig = await requireActivityConfig(nextActivityType);
  const nextType = patch.type || activityConfig.baseType || current.type;
  if (String(activityConfig.baseType || "").trim() !== String(nextType || "").trim()) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.details = { fields: { type: "INVALID_ACTIVITY_BASE_TYPE" } };
    throw err;
  }

  const storeDepartment = resolveStoreDepartmentForWrite({
    activityType: activityConfig.activityType,
    department:
      patch.department === undefined ? current.store_department : patch.department,
  });

  const activityChanged =
    patch.activityType &&
    String(patch.activityType).trim().toLowerCase() !==
      String(current.activity_type || "").trim().toLowerCase();
  const shouldClearDiscovery =
    activityChanged && activityConfig.hasDiscoverySubcategories !== true;
  const requestedDiscoverySubcategory = shouldClearDiscovery
    ? null
    : patch.discoverySubcategory === undefined
      ? current.discovery_subcategory
      : patch.discoverySubcategory;
  const requestedDiscoverySubcategories = shouldClearDiscovery
    ? []
    : patch.discoverySubcategories === null ||
        patch.discoverySubcategories === undefined
      ? undefined
      : patch.discoverySubcategories;
  const requestedDiscoverySelectAll = shouldClearDiscovery
    ? false
    : patch.discoverySelectAll === null || patch.discoverySelectAll === undefined
      ? current.discovery_select_all === true
      : patch.discoverySelectAll === true;
  const discoverySelection = await requireValidDiscoverySelection(
    activityConfig.activityType,
    {
      discoverySubcategory: requestedDiscoverySubcategory,
      discoverySubcategories: requestedDiscoverySubcategories,
      discoverySelectAll: requestedDiscoverySelectAll,
    }
  );

  const updated = await adminRepo.updateManagedMerchantProfile({
    merchantId: safeMerchantId,
    name: patch.name,
    type: nextType,
    activityType: activityConfig.activityType,
    department: storeDepartment,
    discoverySubcategory: discoverySelection.legacyDiscoverySubcategory,
    discoverySubcategories: discoverySelection.discoverySubcategories,
    discoverySelectAll: discoverySelection.discoverySelectAll,
    description: patch.description,
    phone: patch.phone,
  });

  await logAdminAudit({
    actor,
    actionKey: "admin.merchant.profile.updated",
    summary: `Merchant ${updated?.name || safeMerchantId} profile updated by admin`,
    targetType: "merchant",
    targetId: safeMerchantId,
    targetLabel: updated?.name || current.name,
    metadata: {
      previousName: current.name,
      nextName: updated?.name,
      previousActivityType: current.activity_type,
      nextActivityType: updated?.activity_type,
    },
  });

  return { merchant: mapManagedMerchant(updated) };
}

export async function toggleMerchantDisabled(merchantId, isDisabled, adminUserId) {
  const row = await adminRepo.setMerchantDisabled(Number(merchantId), isDisabled);
  if (!row) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  await createManyNotifications(
    [
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: row.is_disabled
              ? "owner_merchant_disabled"
              : "owner_merchant_enabled",
            title: row.is_disabled ? "تم تعطيل المتجر" : "تم تفعيل المتجر",
            body: row.is_disabled
              ? `تم تعطيل متجر ${row.name} مؤقتاً من الإدارة`
              : `تمت إعادة تفعيل متجر ${row.name}`,
            merchantId: row.id,
            payload: {
              merchantId: row.id,
              isDisabled: row.is_disabled,
              changedBy: Number(adminUserId),
            },
          }
        : null,
    ].filter(Boolean)
  );

  await logAdminAudit({
    actor: adminUserId,
    actionKey: row.is_disabled
      ? "admin.merchant.disabled"
      : "admin.merchant.enabled",
    summary: row.is_disabled
      ? `عطّل المتجر ${row.name}`
      : `أعاد تفعيل المتجر ${row.name}`,
    targetType: "merchant",
    targetId: Number(row.id),
    targetLabel: row.name,
    metadata: {
      isDisabled: row.is_disabled === true,
      ownerUserId: row.owner_user_id || null,
    },
  });

  return {
    id: row.id,
    name: row.name,
    isDisabled: row.is_disabled,
  };
}

export async function listApprovalInbox(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 60);

  const fallbackInboxTask = async (task, fallbackValue) => {
    try {
      return await task();
    } catch (error) {
      if (isSchemaCompatibilityError(error)) {
        return fallbackValue;
      }
      throw error;
    }
  };

  const [
    pendingMerchants,
    pendingDeliveryAccounts,
    pendingTaxiCaptainAccounts,
    pendingSettlements,
    pendingTaxiCash,
    pendingTaxiProfileEdits,
    pendingProfileCoreChanges,
  ] = await Promise.all([
    getPendingMerchants(),
    listPendingDeliveryAccounts(),
    listPendingTaxiCaptainAccounts(),
    getPendingSettlements(),
    fallbackInboxTask(
      () => listPendingTaxiCaptainCashPayments({ limit }),
      { items: [], total: 0 }
    ),
    fallbackInboxTask(
      () => listPendingTaxiCaptainProfileEditRequests({ limit }),
      { items: [], total: 0 }
    ),
    fallbackInboxTask(
      () => listProfileCoreChangeRequests({ status: "pending", limit }),
      { items: [], nextCursor: null }
    ),
  ]);

  const items = [
    ...pendingMerchants.map((item) => ({
      id: `merchant:${item.id}`,
      kind: "merchant",
      targetId: Number(item.id),
      title: "موافقة متجر",
      subject: item.name || `متجر #${item.id}`,
      subtitle: [item.owner_full_name, item.owner_phone].filter(Boolean).join(" • "),
      meta: item.type ? `النوع: ${item.type}` : null,
      createdAt: toIsoOrNull(item.created_at),
    })),
    ...pendingDeliveryAccounts.map((item) => ({
      id: `delivery:${item.id}`,
      kind: "delivery",
      targetId: Number(item.id),
      title: "موافقة دلفري",
      subject: item.fullName || item.full_name || `دلفري #${item.id}`,
      subtitle: [item.phone, item.block, item.buildingNumber || item.building_number]
          .filter(Boolean)
          .join(" • "),
      meta: item.vehicleType || item.vehicle_type || null,
      createdAt: toIsoOrNull(item.createdAt || item.created_at),
    })),
    ...pendingTaxiCaptainAccounts.map((item) => ({
      id: `taxi_captain:${item.id}`,
      kind: "taxi_captain",
      targetId: Number(item.id),
      title: "موافقة كابتن تكسي",
      subject: item.fullName || item.full_name || `كابتن #${item.id}`,
      subtitle: [item.phone, item.block, item.buildingNumber || item.building_number]
          .filter(Boolean)
          .join(" • "),
      meta:
        [item.vehicleType || item.vehicle_type, item.carMake || item.car_make, item.carModel || item.car_model]
            .filter(Boolean)
            .join(" • ") || null,
      createdAt: toIsoOrNull(item.createdAt || item.created_at),
    })),
    ...pendingSettlements.map((item) => ({
      id: `settlement:${item.id}`,
      kind: "settlement",
      targetId: Number(item.id),
      title: "تسوية مالية",
      subject: item.merchant_name || `تسوية #${item.id}`,
      subtitle: [item.owner_full_name, item.owner_phone].filter(Boolean).join(" • "),
      meta:
        item.amount != null ? `القيمة: ${Number(item.amount).toFixed(0)} د.ع` : null,
      createdAt: toIsoOrNull(item.requested_at),
    })),
    ...pendingTaxiCash.items.map((item) => ({
      id: `taxi-cash:${item.captainUserId}`,
      kind: "taxi_cash",
      targetId: Number(item.captainUserId),
      title: "تسديد اشتراك تكسي",
      subject: item.fullName || `كابتن #${item.captainUserId}`,
      subtitle: [item.phone, item.block, item.buildingNumber].filter(Boolean).join(" • "),
      meta:
        item.subscription?.dueAmountIqd != null
            ? `المبلغ المستحق: ${Number(item.subscription.dueAmountIqd).toFixed(0)} د.ع`
            : null,
      createdAt: toIsoOrNull(item.cashPaymentRequestedAt),
    })),
    ...pendingTaxiProfileEdits.items.map((item) => ({
      id: `taxi-profile:${item.id}`,
      kind: "taxi_profile_edit",
      targetId: Number(item.id),
      title: "تعديل بيانات كابتن",
      subject: item.fullName || `طلب #${item.id}`,
      subtitle: [item.phone, item.block, item.buildingNumber].filter(Boolean).join(" • "),
      meta: `عدد التعديلات: ${Object.keys(item.requestedChanges || {}).length}`,
      createdAt: toIsoOrNull(item.requestedAt),
    })),
    ...pendingProfileCoreChanges.items.map((item) => ({
      id: `profile-core:${item.id}`,
      kind: "profile_core_change",
      targetId: Number(item.id),
      title: "طلب تعديل بيانات أساسية",
      subject: item.userFullName || `طلب #${item.id}`,
      subtitle: [item.userPhone].filter(Boolean).join(" • "),
      meta: "تعديل الاسم أو اسم المستخدم",
      createdAt: toIsoOrNull(item.createdAt),
    })),
  ]
    .sort((a, b) => {
      const aMs = a.createdAt ? Date.parse(a.createdAt) : 0;
      const bMs = b.createdAt ? Date.parse(b.createdAt) : 0;
      return bMs - aMs;
    })
    .slice(0, limit);

  const counts = {
    merchants: pendingMerchants.length,
    deliveryAccounts: pendingDeliveryAccounts.length,
    taxiCaptainAccounts: pendingTaxiCaptainAccounts.length,
    settlements: pendingSettlements.length,
    taxiCashPayments: pendingTaxiCash.total,
    taxiProfileEdits: pendingTaxiProfileEdits.total,
    profileCoreChanges: pendingProfileCoreChanges.items.length,
  };

  return {
    items,
    total: Object.values(counts).reduce((sum, value) => sum + Number(value || 0), 0),
    counts,
    limit,
  };
}

function mapPendingDeliveryAccount(row) {
  return {
    id: row.id,
    fullName: row.full_name,
    phone: row.phone,
    block: row.block,
    buildingNumber: row.building_number,
    apartment: row.apartment,
    createdAt: row.created_at,
    vehicleType: row.vehicle_type,
    carMake: row.car_make,
    carModel: row.car_model,
    carYear: row.car_year,
    carColor: row.car_color,
    plateNumber: row.plate_number,
    profileImageUrl: row.profile_image_url,
    carImageUrl: row.car_image_url,
  };
}

export async function listPendingDeliveryAccounts() {
  const rows = await adminRepo.listPendingDeliveryAccounts();
  return rows.map(mapPendingDeliveryAccount);
}

export async function listPendingTaxiCaptainAccounts() {
  const rows = await adminRepo.listPendingTaxiCaptainAccounts();
  return rows.map(mapPendingDeliveryAccount);
}

export async function approveDeliveryAccount(deliveryUserId, adminUserId) {
  const approved = await adminRepo.approveDeliveryAccount(
    Number(deliveryUserId),
    toActorUserId(adminUserId)
  );

  if (!approved) {
    const err = new Error("DELIVERY_ACCOUNT_NOT_FOUND_OR_ALREADY_APPROVED");
    err.status = 404;
    throw err;
  }

  await commerceRepo.syncCourierDriverAffiliation({
    userId: Number(approved.id),
    driverType: "app_driver",
    merchantId: null,
    merchantIdSet: true,
    actorUserId: toActorUserId(adminUserId),
    source: "admin_approval",
  });

  await createManyNotifications([
    {
      userId: Number(approved.id),
      type: "delivery_account_approved",
      title: "تمت الموافقة على حسابك",
      body: "تمت مراجعة بياناتك ويمكنك الآن تسجيل الدخول كتطبيق دلفري.",
      payload: {
        deliveryUserId: Number(approved.id),
      },
    },
  ]);

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.delivery.approved",
    summary: `وافق على حساب الدلفري ${approved.full_name}`,
    targetType: "user",
    targetId: Number(approved.id),
    targetLabel: approved.full_name,
    metadata: {
      phone: approved.phone,
      role: "delivery",
      driverType: "app_driver",
    },
  });

  return {
    id: Number(approved.id),
    fullName: approved.full_name,
    phone: approved.phone,
    driverType: "app_driver",
  };
}

export async function approveTaxiCaptainAccount(captainUserId, adminUserId) {
  const approved = await adminRepo.approveTaxiCaptainAccount(
    Number(captainUserId),
    toActorUserId(adminUserId)
  );

  if (!approved) {
    const err = new Error("TAXI_CAPTAIN_ACCOUNT_NOT_FOUND_OR_ALREADY_APPROVED");
    err.status = 404;
    throw err;
  }

  await createManyNotifications([
    {
      userId: Number(approved.id),
      type: "taxi_captain_account_approved",
      title: "تمت الموافقة على حسابك",
      body: "تمت مراجعة بياناتك ويمكنك الآن تسجيل الدخول ككابتن تكسي.",
      payload: {
        captainUserId: Number(approved.id),
      },
    },
  ]);

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.taxi_captain.approved",
    summary: `وافق على حساب كابتن التكسي ${approved.full_name}`,
    targetType: "user",
    targetId: Number(approved.id),
    targetLabel: approved.full_name,
    metadata: {
      phone: approved.phone,
      role: "taxi_captain",
    },
  });

  return {
    id: Number(approved.id),
    fullName: approved.full_name,
    phone: approved.phone,
    role: "taxi_captain",
  };
}

export async function updateDeliveryDriverProfile({
  deliveryUserId,
  actor = {},
  driverType,
  merchantId = null,
}) {
  const current = await adminRepo.getDeliveryUserProfileById(Number(deliveryUserId));
  if (!current) {
    const err = new Error("DELIVERY_ACCOUNT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const normalizedDriverType = normalizeDriverType(driverType, "app_driver");
  let merchant = null;
  if (normalizedDriverType === "store_driver" || merchantId != null) {
    merchant = await adminRepo.getMerchantById(Number(merchantId));
    if (!merchant) {
      const err = new Error("MERCHANT_NOT_FOUND");
      err.status = 404;
      throw err;
    }
  }

  const currentDriverType = normalizeDriverType(current.driver_type, "app_driver");
  const currentMerchantId =
    current.merchant_id == null ? null : Number(current.merchant_id);
  const nextMerchantId = merchantId == null ? null : Number(merchantId);
  if (
    currentDriverType === normalizedDriverType &&
    currentMerchantId === nextMerchantId
  ) {
    return {
      id: Number(current.id),
      fullName: current.full_name,
      phone: current.phone,
      driverType: currentDriverType,
      merchantId: currentMerchantId,
      merchantName: current.merchant_name || null,
    };
  }

  await commerceRepo.syncCourierDriverAffiliation({
    userId: Number(deliveryUserId),
    driverType: normalizedDriverType,
    merchantId: merchantId == null ? null : Number(merchantId),
    merchantIdSet: true,
    actorUserId: toActorUserId(actor),
    source: "admin_update",
  });

  const updated = await adminRepo.getDeliveryUserProfileById(Number(deliveryUserId));
  await logAdminAudit({
    actor,
    actionKey: "admin.delivery.driver_type.updated",
    summary: `Updated delivery type for ${current.full_name}`,
    targetType: "user",
    targetId: Number(deliveryUserId),
    targetLabel: current.full_name,
    metadata: {
      oldDriverType: current.driver_type || null,
      newDriverType: normalizedDriverType,
      oldMerchantId: current.merchant_id == null ? null : Number(current.merchant_id),
      newMerchantId: merchantId == null ? null : Number(merchantId),
      newMerchantName: merchant?.name || null,
    },
  });

  return {
    id: Number(updated?.id || deliveryUserId),
    fullName: updated?.full_name || current.full_name,
    phone: updated?.phone || current.phone,
    driverType: updated?.driver_type || normalizedDriverType,
    merchantId:
      updated?.merchant_id == null ? null : Number(updated.merchant_id),
    merchantName: updated?.merchant_name || null,
  };
}

export async function listAdminAuditFeed(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 40);
  const beforeId = clampInt(query?.beforeId, 1, Number.MAX_SAFE_INTEGER, null);
  const rows = await adminRepo.listAdminAuditFeed({ limit, beforeId });
  const items = rows.map((row) => ({
    id: Number(row.id),
    actorUserId: row.actor_user_id == null ? null : Number(row.actor_user_id),
    actorFullName: row.actor_full_name || null,
    actorPhone: row.actor_phone || null,
    actorRole: row.actor_role || null,
    actionKey: row.action_key,
    summary: row.summary,
    targetType: row.target_type || null,
    targetId: row.target_id == null ? null : Number(row.target_id),
    targetLabel: row.target_label || null,
    metadata:
      row.metadata && typeof row.metadata === "object" ? row.metadata : null,
    createdAt: toIsoOrNull(row.created_at),
  }));

  return {
    items,
    limit,
    nextCursor:
      items.length >= limit ? Number(items[items.length - 1].id || 0) || null : null,
  };
}

export async function printOrdersReport(period) {
  const normalizedPeriod = String(period || "day").toLowerCase();
  return ordersRepo.listAdminOrdersForReport(normalizedPeriod);
}

export async function getAdminOrdersOverview(query = {}) {
  return ordersRepo.listAdminMerchantOrderOverview({
    status: query?.status,
    period: query?.period,
    from: query?.from,
    to: query?.to,
    search: query?.search,
    limit: query?.limit,
    offset: query?.offset,
  });
}

export async function getAdminMerchantOrdersOverview(merchantId, query = {}) {
  return ordersRepo.listAdminMerchantOrdersOverview({
    merchantId,
    status: query?.status,
    period: query?.period,
    from: query?.from,
    to: query?.to,
    limit: query?.limit,
    offset: query?.offset,
  });
}

export async function listCustomerInsights(query) {
  return behaviorService.listCustomersInsight(query || {});
}

export async function getCustomerInsightDetails(customerUserId) {
  return behaviorService.getCustomerFullInsight(Number(customerUserId));
}

export async function listPendingTaxiCaptainCashPayments(query = {}) {
  const limit = Math.max(1, Math.min(300, Number(query?.limit) || 100));
  const items = await taxiService.listPendingCaptainCashPayments({ limit });
  return {
    items,
    total: items.length,
  };
}

export async function confirmTaxiCaptainCashPayment({
  captainUserId,
  cycleDays,
  adminUserId,
}) {
  const result = await taxiService.confirmCaptainCashPaymentByAdmin({
    captainUserId: Number(captainUserId),
    adminUserId: toActorUserId(adminUserId),
    cycleDays: Number(cycleDays) || 30,
  });

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.taxi.cash_payment.confirmed",
    summary: `أكد تسديد اشتراك كابتن التكسي #${Number(captainUserId)}`,
    targetType: "taxi_captain",
    targetId: Number(captainUserId),
    targetLabel: `كابتن #${Number(captainUserId)}`,
    metadata: {
      cycleDays: Number(cycleDays) || 30,
      remainingDays: result.subscription?.remainingDays || null,
    },
  });

  return result;
}

export async function setTaxiCaptainDiscount({
  captainUserId,
  discountPercent,
  adminUserId,
}) {
  const result = await taxiService.setCaptainDiscountByAdmin({
    captainUserId: Number(captainUserId),
    discountPercent: Number(discountPercent),
    adminUserId: toActorUserId(adminUserId),
  });

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.taxi.discount.updated",
    summary: `حدّث خصم اشتراك كابتن التكسي #${Number(captainUserId)} إلى ${Number(discountPercent)}%`,
    targetType: "taxi_captain",
    targetId: Number(captainUserId),
    targetLabel: `كابتن #${Number(captainUserId)}`,
    metadata: {
      discountPercent: Number(discountPercent),
      discountedMonthlyFeeIqd: result.subscription?.discountedMonthlyFeeIqd || null,
    },
  });

  return result;
}

export async function listPendingTaxiCaptainProfileEditRequests(query = {}) {
  const limit = Math.max(1, Math.min(300, Number(query?.limit) || 100));
  const items = await taxiService.listPendingCaptainProfileEditRequests({ limit });
  return {
    items,
    total: items.length,
  };
}

export async function approveTaxiCaptainProfileEditRequest({
  requestId,
  adminUserId,
  adminNote,
}) {
  const result = await taxiService.reviewCaptainProfileEditRequestByAdmin({
    requestId: Number(requestId),
    decision: "approved",
    adminUserId: toActorUserId(adminUserId),
    adminNote: adminNote || null,
  });

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.taxi.profile_edit.approved",
    summary: `وافق على تعديل بيانات كابتن التكسي #${result.captainUserId}`,
    targetType: "taxi_profile_edit_request",
    targetId: Number(requestId),
    targetLabel: result.captain?.fullName || `طلب #${Number(requestId)}`,
    metadata: {
      captainUserId: result.captainUserId,
      adminNote: result.adminNote || null,
      requestedChangesCount: Object.keys(result.requestedChanges || {}).length,
    },
  });

  return result;
}

export async function rejectTaxiCaptainProfileEditRequest({
  requestId,
  adminUserId,
  adminNote,
}) {
  const result = await taxiService.reviewCaptainProfileEditRequestByAdmin({
    requestId: Number(requestId),
    decision: "rejected",
    adminUserId: toActorUserId(adminUserId),
    adminNote: adminNote || null,
  });

  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.taxi.profile_edit.rejected",
    summary: `رفض تعديل بيانات كابتن التكسي #${result.captainUserId}`,
    targetType: "taxi_profile_edit_request",
    targetId: Number(requestId),
    targetLabel: result.captain?.fullName || `طلب #${Number(requestId)}`,
    metadata: {
      captainUserId: result.captainUserId,
      adminNote: result.adminNote || null,
      requestedChangesCount: Object.keys(result.requestedChanges || {}).length,
    },
  });

  return result;
}

function mapAdBoardItem(row) {
  return {
    id: Number(row.id),
    placement: row.placement || "HOME_MAIN",
    title: row.title,
    titleAr: row.title_ar || null,
    titleEn: row.title_en || null,
    subtitle: row.subtitle,
    subtitleAr: row.subtitle_ar || null,
    subtitleEn: row.subtitle_en || null,
    imageUrl: row.image_url,
    mobileImageUrl: row.mobile_image_url || null,
    activityType: row.activity_type || null,
    badgeLabel: row.badge_label,
    ctaLabel: row.cta_label,
    ctaLabelAr: row.cta_label_ar || null,
    ctaLabelEn: row.cta_label_en || null,
    type: row.cta_target_type,
    impressionCount: Number(row.impression_count || 0),
    clickCount: Number(row.click_count || 0),
    targetId: row.target_id == null
      ? row.merchant_id == null
        ? null
        : Number(row.merchant_id)
      : Number(row.target_id),
    targetRoute: row.target_route || null,
    promoCode: row.promo_code || null,
    category: row.category || null,
    externalLink: row.external_link || null,
    ctaTargetType: row.cta_target_type,
    ctaTargetValue: row.cta_target_value,
    merchantId: row.merchant_id ? Number(row.merchant_id) : null,
    merchantName: row.merchant_name || null,
    merchantType: row.merchant_type || null,
    merchantIsApproved: row.merchant_is_approved === true,
    merchantIsDisabled: row.merchant_is_disabled === true,
    priority: Number(row.priority || 0),
    isActive: row.is_active === true,
    startsAt: row.starts_at ? new Date(row.starts_at).toISOString() : null,
    endsAt: row.ends_at ? new Date(row.ends_at).toISOString() : null,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : null,
  };
}

async function assertMerchantExists(merchantId) {
  if (!merchantId) return;
  const merchant = await adminRepo.getMerchantById(merchantId);
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

function parsePositiveIntegerOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

function normalizeActionType(value, fallback = "none") {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized || fallback;
}

const AD_BOARD_PLACEMENTS = new Set([
  "HOME_MAIN",
  "MARKETPLACE_HOME",
  "MARKETPLACE_CATEGORY",
]);

/// Validates+normalizes the ad placement. Undefined placement defaults to the
/// legacy HOME_MAIN so existing single-placement callers keep working.
function normalizeAdPlacement(value, { required = false } = {}) {
  if (value === undefined || value === null || value === "") {
    if (required) {
      const err = new Error("AD_BOARD_PLACEMENT_REQUIRED");
      err.status = 400;
      throw err;
    }
    return "HOME_MAIN";
  }
  const normalized = String(value).trim().toUpperCase();
  if (!AD_BOARD_PLACEMENTS.has(normalized)) {
    const err = new Error("AD_BOARD_PLACEMENT_INVALID");
    err.status = 400;
    err.details = { placement: normalized };
    throw err;
  }
  return normalized;
}

function resolveExternalLinkFromPayload(payload = {}) {
  const direct = String(payload.externalLink || "").trim();
  if (direct) return direct;
  return String(payload.ctaTargetValue || "").trim();
}

function assertExternalLinkAllowed(link) {
  let parsed = null;
  try {
    parsed = new URL(link);
  } catch (_) {
    const err = new Error("AD_BOARD_EXTERNAL_LINK_INVALID");
    err.status = 400;
    throw err;
  }

  if (parsed.protocol !== "https:") {
    const err = new Error("AD_BOARD_EXTERNAL_LINK_HTTPS_ONLY");
    err.status = 400;
    throw err;
  }

  const allowedHosts = (env.adsExternalAllowedHosts || [])
    .map((entry) => String(entry || "").trim().toLowerCase())
    .filter(Boolean);
  if (!allowedHosts.length) return;

  const host = String(parsed.host || "").trim().toLowerCase();
  const isAllowed = allowedHosts.some((allowed) => {
    if (host === allowed) return true;
    return host.endsWith(`.${allowed}`);
  });
  if (!isAllowed) {
    const err = new Error("AD_BOARD_EXTERNAL_LINK_HOST_NOT_ALLOWED");
    err.status = 400;
    err.details = { host };
    throw err;
  }
}

async function assertProductTargetValid({
  ctaTargetType,
  ctaTargetValue,
  merchantId,
}) {
  if (String(ctaTargetType || "").trim() !== "product") return;

  const safeMerchantId = parsePositiveIntegerOrNull(merchantId);
  const safeProductId = parsePositiveIntegerOrNull(ctaTargetValue);
  if (!safeMerchantId || !safeProductId) {
    const err = new Error("AD_BOARD_PRODUCT_TARGET_INVALID");
    err.status = 400;
    err.details = {
      merchantId: safeMerchantId,
      productId: safeProductId,
    };
    throw err;
  }

  const product = await adminRepo.getMerchantProductById(safeMerchantId, safeProductId);
  if (!product) {
    const err = new Error("AD_BOARD_PRODUCT_NOT_FOUND");
    err.status = 404;
    err.details = {
      merchantId: safeMerchantId,
      productId: safeProductId,
    };
    throw err;
  }
}

async function assertAdActionPayload(payload = {}) {
  const actionType = normalizeActionType(payload.ctaTargetType, "none");
  const merchantId = parsePositiveIntegerOrNull(payload.merchantId);
  const targetId = parsePositiveIntegerOrNull(payload.targetId);
  const ctaTargetValue = String(payload.ctaTargetValue || "").trim();
  const targetRoute = String(payload.targetRoute || "").trim();
  const category = String(payload.category || "").trim();
  const promoCode = String(payload.promoCode || "").trim();
  const externalLink = resolveExternalLinkFromPayload(payload);

  if (actionType === "store_ad") {
    if (!merchantId && !targetId) {
      const err = new Error("AD_BOARD_STORE_TARGET_REQUIRED");
      err.status = 400;
      throw err;
    }
    return;
  }

  if (actionType === "merchant") {
    if (!merchantId) {
      const err = new Error("AD_BOARD_MERCHANT_REQUIRED");
      err.status = 400;
      throw err;
    }
    return;
  }

  if (actionType === "promo_code") {
    if (!promoCode) {
      const err = new Error("AD_BOARD_PROMO_CODE_REQUIRED");
      err.status = 400;
      throw err;
    }
    return;
  }

  if (actionType === "category_ad") {
    if (!category && !ctaTargetValue) {
      const err = new Error("AD_BOARD_CATEGORY_REQUIRED");
      err.status = 400;
      throw err;
    }
    return;
  }

  if (actionType === "external_link" || actionType === "url") {
    if (!externalLink) {
      const err = new Error("AD_BOARD_EXTERNAL_LINK_REQUIRED");
      err.status = 400;
      throw err;
    }
    assertExternalLinkAllowed(externalLink);
    return;
  }

  if (actionType === "internal_route") {
    if (!targetRoute && !ctaTargetValue) {
      const err = new Error("AD_BOARD_TARGET_ROUTE_REQUIRED");
      err.status = 400;
      throw err;
    }
  }
}

export async function listAdBoardItems() {
  const rows = await adminRepo.listAdBoardItems();
  return rows.map(mapAdBoardItem);
}

export async function listAdBoardMerchantProducts(merchantId, { limit = 300 } = {}) {
  const safeMerchantId = parsePositiveIntegerOrNull(merchantId);
  if (!safeMerchantId) {
    const err = new Error("MERCHANT_ID_INVALID");
    err.status = 400;
    throw err;
  }
  await assertMerchantExists(safeMerchantId);
  const rows = await adminRepo.listMerchantProductsForAdBoard(safeMerchantId, limit);
  return rows.map((row) => ({
    id: Number(row.id),
    merchantId: Number(row.merchant_id),
    name: row.name,
    imageUrl: row.image_url || null,
    price: Number(row.price || 0),
    discountedPrice:
      row.discounted_price == null ? null : Number(row.discounted_price),
    isAvailable: row.is_available === true,
  }));
}

export async function createAdBoardItem(dto, adminUserId) {
  await assertMerchantExists(dto.merchantId);
  await assertProductTargetValid({
    ctaTargetType: dto.ctaTargetType,
    ctaTargetValue: dto.ctaTargetValue,
    merchantId: dto.merchantId,
  });
  await assertAdActionPayload(dto);
  const placement = normalizeAdPlacement(dto.placement);
  const created = await adminRepo.createAdBoardItem({
    ...dto,
    placement,
    actorUserId: toActorUserId(adminUserId),
  });
  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.ad_board.created",
    summary: `أنشأ مادة جديدة في لوحة الإعلانات: ${created?.title || `#${created?.id || ""}`}`,
    targetType: "ad_board_item",
    targetId: Number(created?.id || 0) || null,
    targetLabel: created?.title || null,
    metadata: {
      merchantId: created?.merchant_id || null,
      isActive: created?.is_active === true,
    },
  });
  return mapAdBoardItem(created);
}

export async function updateAdBoardItem(itemId, dto, adminUserId) {
  const existing = await adminRepo.getAdBoardItemById(itemId);
  if (!existing) {
    const err = new Error("AD_BOARD_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (Object.prototype.hasOwnProperty.call(dto, "merchantId")) {
    await assertMerchantExists(dto.merchantId);
  }

  const nextPayload = {
    ctaTargetType: Object.prototype.hasOwnProperty.call(dto, "ctaTargetType")
      ? dto.ctaTargetType
      : existing.cta_target_type,
    ctaTargetValue: Object.prototype.hasOwnProperty.call(dto, "ctaTargetValue")
      ? dto.ctaTargetValue
      : existing.cta_target_value,
    merchantId: Object.prototype.hasOwnProperty.call(dto, "merchantId")
      ? dto.merchantId
      : existing.merchant_id,
    targetId: Object.prototype.hasOwnProperty.call(dto, "targetId")
      ? dto.targetId
      : existing.target_id,
    targetRoute: Object.prototype.hasOwnProperty.call(dto, "targetRoute")
      ? dto.targetRoute
      : existing.target_route,
    promoCode: Object.prototype.hasOwnProperty.call(dto, "promoCode")
      ? dto.promoCode
      : existing.promo_code,
    category: Object.prototype.hasOwnProperty.call(dto, "category")
      ? dto.category
      : existing.category,
    externalLink: Object.prototype.hasOwnProperty.call(dto, "externalLink")
      ? dto.externalLink
      : existing.external_link,
  };
  await assertProductTargetValid(nextPayload);
  await assertAdActionPayload(nextPayload);

  const patch = { ...dto };
  if (Object.prototype.hasOwnProperty.call(dto, "placement")) {
    patch.placement = normalizeAdPlacement(dto.placement, { required: true });
  }

  const updated = await adminRepo.updateAdBoardItem(
    itemId,
    patch,
    toActorUserId(adminUserId)
  );
  if (!updated) {
    const err = new Error("AD_BOARD_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await logAdminAudit({
    actor: adminUserId,
    actionKey: "admin.ad_board.updated",
    summary: `حدّث مادة لوحة الإعلانات: ${updated?.title || `#${itemId}`}`,
    targetType: "ad_board_item",
    targetId: Number(itemId),
    targetLabel: updated?.title || null,
    metadata: {
      updatedFields: Object.keys(dto || {}),
      merchantId: updated?.merchant_id || null,
      isActive: updated?.is_active === true,
    },
  });
  return mapAdBoardItem(updated);
}

export async function deleteAdBoardItem(itemId, actor = {}) {
  const deleted = await adminRepo.deleteAdBoardItem(itemId);
  if (!deleted) {
    const err = new Error("AD_BOARD_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await logAdminAudit({
    actor,
    actionKey: "admin.ad_board.deleted",
    summary: `حذف مادة من لوحة الإعلانات #${Number(itemId)}`,
    targetType: "ad_board_item",
    targetId: Number(itemId),
    targetLabel: `#${Number(itemId)}`,
    metadata: null,
  });
  return { id: Number(deleted.id) };
}

function mapPostReportItem(row) {
  const reports = Array.isArray(row?.reports) ? row.reports : [];
  return {
    postId: Number(row.post_id),
    authorUserId: Number(row.author_user_id),
    authorFullName: row.author_full_name || "",
    authorPhone: row.author_phone || "",
    caption: row.caption || "",
    mediaUrl: row.media_url || null,
    mediaKind: row.media_kind || null,
    postKind: row.post_kind || "normal",
    audienceScopeType: row.audience_scope_type || "global",
    audienceScopeCode: row.audience_scope_code || null,
    moderationStatus: row.moderation_status || "approved",
    moderationNote: row.moderation_note || null,
    moderationRequestedAt: row.moderation_requested_at || null,
    postCreatedAt: row.post_created_at || null,
    postUpdatedAt: row.post_updated_at || null,
    reportsCount: Number(row.reports_count || 0),
    lastReportedAt: row.last_reported_at || null,
    reports: reports.map((item) => ({
      id: Number(item.id || 0),
      reason: item.reason || "",
      details: item.details || null,
      createdAt: item.createdAt || item.created_at || null,
      reporterUserId:
        item.reporterUserId == null && item.reporter_user_id == null
          ? null
          : Number(item.reporterUserId || item.reporter_user_id || 0),
      reporterFullName: item.reporterFullName || item.reporter_full_name || null,
      reporterPhone: item.reporterPhone || item.reporter_phone || null,
      source: String(item.source || "user").trim().toLowerCase(),
    })),
  };
}

function mapStoryReportItem(row) {
  const reports = Array.isArray(row?.reports) ? row.reports : [];
  return {
    storyId: Number(row.story_id),
    authorUserId: Number(row.author_user_id),
    authorFullName: row.author_full_name || "",
    authorPhone: row.author_phone || "",
    caption: row.caption || "",
    mediaUrl: row.media_url || null,
    mediaKind: row.media_kind || null,
    moderationStatus: row.moderation_status || "approved",
    moderationNote: row.moderation_note || null,
    moderationRequestedAt: row.moderation_requested_at || null,
    storyCreatedAt: row.story_created_at || null,
    storyUpdatedAt: row.story_updated_at || null,
    expiresAt: row.expires_at || null,
    reportsCount: Number(row.reports_count || 0),
    lastReportedAt: row.last_reported_at || null,
    reports: reports.map((item) => ({
      id: Number(item.id || 0),
      reason: item.reason || "",
      details: item.details || null,
      createdAt: item.createdAt || item.created_at || null,
      reporterUserId:
        item.reporterUserId == null && item.reporter_user_id == null
          ? null
          : Number(item.reporterUserId || item.reporter_user_id || 0),
      reporterFullName: item.reporterFullName || item.reporter_full_name || null,
      reporterPhone: item.reporterPhone || item.reporter_phone || null,
    })),
  };
}

function mapResidenceChangeRequestItem(row) {
  const current = row.current_snapshot_json || {};
  const requested = row.requested_snapshot_json || {};
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    userFullName: row.user_full_name || "",
    userPhone: row.user_phone || "",
    status: String(row.status || "pending").trim().toLowerCase(),
    currentSnapshot: current,
    requestedSnapshot: requested,
    note: row.note || null,
    documentImageUrl: row.document_image_url || null,
    reviewNote: row.review_note || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedByFullName: row.reviewed_by_full_name || null,
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapProfileCoreChangeRequestItem(row) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    userFullName: row.user_full_name || "",
    userPhone: row.user_phone || "",
    status: String(row.status || "pending").trim().toLowerCase(),
    currentSnapshot: row.current_snapshot_json || {},
    requestedSnapshot: row.requested_snapshot_json || {},
    reviewNote: row.review_note || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedByFullName: row.reviewed_by_full_name || null,
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapSocialCapabilityRestrictionItem(row) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    userFullName: row.user_full_name || "",
    userPhone: row.user_phone || "",
    capabilityKey: String(row.capability_key || "").trim().toLowerCase(),
    reason: row.reason || null,
    startsAt: row.starts_at || null,
    endsAt: row.ends_at || null,
    createdByUserId:
      row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    createdByFullName: row.created_by_full_name || null,
    revokedAt: row.revoked_at || null,
    revokedByUserId:
      row.revoked_by_user_id == null ? null : Number(row.revoked_by_user_id),
    revokedByFullName: row.revoked_by_full_name || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    isActive:
      row.revoked_at == null &&
      (!row.ends_at || new Date(row.ends_at).getTime() > Date.now()),
  };
}

export async function listSocialPostReports(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  const beforePostId =
    query?.beforePostId == null || query.beforePostId === ""
      ? null
      : Number(query.beforePostId);
  const status = String(query?.status || "open").trim().toLowerCase();
  const rows = await adminRepo.listPostReports({
    status,
    limit,
    beforePostId:
      beforePostId != null && Number.isInteger(beforePostId) && beforePostId > 0
        ? beforePostId
        : null,
  });
  return {
    items: rows.map(mapPostReportItem),
    nextCursor:
      rows.length > 0
        ? Number(rows[rows.length - 1]?.post_id || 0) || null
        : null,
  };
}

export async function listSocialStoryReports(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  const beforeStoryId =
    query?.beforeStoryId == null || query.beforeStoryId === ""
      ? null
      : Number(query.beforeStoryId);
  const status = String(query?.status || "open").trim().toLowerCase();
  const rows = await adminRepo.listStoryReports({
    status,
    limit,
    beforeStoryId:
      beforeStoryId != null && Number.isInteger(beforeStoryId) && beforeStoryId > 0
        ? beforeStoryId
        : null,
  });
  return {
    items: rows.map(mapStoryReportItem),
    nextCursor:
      rows.length > 0
        ? Number(rows[rows.length - 1]?.story_id || 0) || null
        : null,
  };
}

export async function listSocialUserReports(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  const beforeId =
    query?.beforeId == null || query.beforeId === ""
      ? null
      : Number(query.beforeId);
  const rows = await adminRepo.listUserReports({
    limit,
    beforeId: beforeId != null && Number.isInteger(beforeId) && beforeId > 0 ? beforeId : null,
  });
  return {
    items: rows.map((row) => ({
      id: Number(row.id),
      reportedUserId: Number(row.reported_user_id),
      reportedUserFullName: row.reported_user_full_name || "",
      reportedUserPhone: row.reported_user_phone || "",
      reporterUserId: Number(row.reporter_user_id),
      reporterFullName: row.reporter_full_name || "",
      reporterPhone: row.reporter_phone || "",
      reason: row.reason || "",
      details: row.details || null,
      createdAt: row.created_at || null,
    })),
    nextCursor:
      rows.length > 0 ? Number(rows[rows.length - 1]?.id || 0) || null : null,
  };
}

export async function listResidenceChangeRequests(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  const beforeId =
    query?.beforeId == null || query.beforeId === "" ? null : Number(query.beforeId);
  const status = String(query?.status || "pending").trim().toLowerCase();
  const rows = await adminRepo.listResidenceChangeRequests({
    status,
    limit,
    beforeId: beforeId != null && Number.isInteger(beforeId) && beforeId > 0 ? beforeId : null,
  });
  return {
    items: rows.map(mapResidenceChangeRequestItem),
    nextCursor:
      rows.length > 0 ? Number(rows[rows.length - 1]?.id || 0) || null : null,
  };
}

export async function listProfileCoreChangeRequests(query = {}) {
  const limit = clampInt(query?.limit, 1, 200, 80);
  const beforeId =
    query?.beforeId == null || query.beforeId === "" ? null : Number(query.beforeId);
  const status = String(query?.status || "pending").trim().toLowerCase();
  let rows = [];
  try {
    rows = await adminRepo.listProfileCoreChangeRequests({
      status,
      limit,
      beforeId:
        beforeId != null && Number.isInteger(beforeId) && beforeId > 0
          ? beforeId
          : null,
    });
  } catch (error) {
    if (!isSchemaCompatibilityError(error)) {
      throw error;
    }
    rows = [];
  }
  return {
    items: rows.map(mapProfileCoreChangeRequestItem),
    nextCursor:
      rows.length > 0 ? Number(rows[rows.length - 1]?.id || 0) || null : null,
  };
}

export async function listSocialCapabilityRestrictionsForUser(userId) {
  const rows = await adminRepo.listSocialCapabilityRestrictionsForUser(userId);
  return {
    items: rows.map(mapSocialCapabilityRestrictionItem),
  };
}

export async function listSocialUsersForModeration(query = {}) {
  const rows = await adminRepo.listSocialUsersForModeration({
    search: query.search || "",
    limit: clampInt(query.limit, 1, 200, 60),
    beforeId:
      query.beforeId == null || query.beforeId === ""
        ? null
        : Number(query.beforeId),
  });
  return {
    items: rows.map(mapSocialModerationUser),
    nextCursor:
      rows.length > 0 ? Number(rows[rows.length - 1]?.id || 0) || null : null,
  };
}

export async function setSocialUserAccountStatus({
  targetUserId,
  isDisabled,
  note = null,
  actor = {},
}) {
  const actorUserId = toActorUserId(actor);
  if (actorUserId <= 0) {
    const err = new Error("FORBIDDEN_ADMIN_ONLY");
    err.status = 403;
    throw err;
  }

  const normalizedTargetUserId = Number(targetUserId);
  if (!Number.isInteger(normalizedTargetUserId) || normalizedTargetUserId <= 0) {
    const err = new Error("VALIDATION_ERROR");
    err.status = 400;
    err.details = { fields: ["userId"] };
    throw err;
  }

  if (normalizedTargetUserId === actorUserId) {
    const err = new Error("SOCIAL_USER_ACTION_SELF_NOT_ALLOWED");
    err.status = 400;
    throw err;
  }

  const [actorUser, targetUser] = await Promise.all([
    adminRepo.findUserForSocialModeration(actorUserId),
    adminRepo.findUserForSocialModeration(normalizedTargetUserId),
  ]);

  if (!actorUser) {
    const err = new Error("FORBIDDEN_ADMIN_ONLY");
    err.status = 403;
    throw err;
  }
  if (!targetUser) {
    const err = new Error("USER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (targetUser.is_super_admin === true) {
    const err = new Error("SUPER_ADMIN_TARGET_FORBIDDEN");
    err.status = 403;
    throw err;
  }

  const actorIsSuperAdmin = actorUser.is_super_admin === true;
  const normalizedTargetRole = String(targetUser.role || "").trim().toLowerCase();
  if (
    !actorIsSuperAdmin &&
    ["admin", "deputy_admin", "accountant", "hr", "owner"].includes(
      normalizedTargetRole
    )
  ) {
    const err = new Error("FORBIDDEN_SUPER_ADMIN_ONLY");
    err.status = 403;
    throw err;
  }

  const normalizedNote = String(note || "").trim();
  const updated = await adminRepo.setSocialUserAccountStatus({
    userId: normalizedTargetUserId,
    isDisabled: isDisabled === true,
    note: normalizedNote || null,
    actedByUserId: actorUserId,
  });
  if (!updated) {
    const err = new Error("USER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  if (isDisabled === true) {
    await revokeAllUserSessions({
      userId: normalizedTargetUserId,
      reason: "account_disabled_by_admin",
    });
    await markUserSessionsRevokedAfter(normalizedTargetUserId);
    invalidateSessionAccessCacheForUser({
      userId: normalizedTargetUserId,
    });
  }

  await createManyNotifications([
    {
      userId: normalizedTargetUserId,
      type:
        isDisabled === true
          ? "social.user.account_disabled"
          : "social.user.account_enabled",
      title: isDisabled === true ? "تم تعطيل حسابك" : "تم تفعيل حسابك",
      body:
        isDisabled === true
          ? normalizedNote || "تم تعطيل الحساب بواسطة الإدارة."
          : "تمت إعادة تفعيل الحساب بواسطة الإدارة.",
      payload: {
        target: "profile",
        reason: normalizedNote || null,
      },
    },
  ]);

  await logAdminAudit({
    actor,
    actionKey:
      isDisabled === true
        ? "admin.social.user.disabled"
        : "admin.social.user.enabled",
    summary:
      isDisabled === true
        ? `عطّل حساب المستخدم #${normalizedTargetUserId}`
        : `فعّل حساب المستخدم #${normalizedTargetUserId}`,
    targetType: "user",
    targetId: normalizedTargetUserId,
    targetLabel: targetUser.full_name || targetUser.username || null,
    metadata: {
      userId: normalizedTargetUserId,
      note: normalizedNote || null,
      isDisabled: isDisabled === true,
    },
  });

  return {
    user: mapSocialModerationUser(updated),
  };
}

export async function createSocialCapabilityRestriction({
  userId,
  capabilityKey,
  reason = null,
  startsAt = null,
  endsAt = null,
  actor = {},
}) {
  const actorUserId = toActorUserId(actor);
  const inserted = await adminRepo.createSocialCapabilityRestriction({
    userId,
    capabilityKey,
    reason,
    startsAt,
    endsAt,
    createdByUserId: actorUserId > 0 ? actorUserId : null,
  });
  if (!inserted) {
    const err = new Error("SOCIAL_RESTRICTION_CREATE_FAILED");
    err.status = 500;
    throw err;
  }

  await createManyNotifications([
    {
      userId: Number(userId),
      type: "social.capability.restricted",
      title: "تم تقييد صلاحية اجتماعية",
      body: reason || `تم تقييد الصلاحية: ${String(capabilityKey || "").trim()}`,
      payload: {
        restrictionId: Number(inserted.id),
        capabilityKey: String(capabilityKey || "").trim().toLowerCase(),
        reason: reason || null,
        startsAt: inserted.starts_at || null,
        endsAt: inserted.ends_at || null,
        target: "social_restriction_notice",
      },
    },
  ]);

  await logAdminAudit({
    actor,
    actionKey: "admin.social.restriction.created",
    summary: `أنشأ قيدًا اجتماعيًا للمستخدم #${Number(userId)}`,
    targetType: "social_capability_restriction",
    targetId: Number(inserted.id),
    targetLabel: String(capabilityKey || "").trim().toLowerCase(),
    metadata: {
      userId: Number(userId),
      capabilityKey: String(capabilityKey || "").trim().toLowerCase(),
      reason: reason || null,
      startsAt: inserted.starts_at || null,
      endsAt: inserted.ends_at || null,
    },
  });

  return {
    restriction: mapSocialCapabilityRestrictionItem(inserted),
  };
}

export async function revokeSocialCapabilityRestriction({
  restrictionId,
  actor = {},
}) {
  const actorUserId = toActorUserId(actor);
  const updated = await adminRepo.revokeSocialCapabilityRestriction({
    restrictionId,
    revokedByUserId: actorUserId,
  });
  if (!updated) {
    const err = new Error("SOCIAL_RESTRICTION_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  await createManyNotifications([
    {
      userId: Number(updated.user_id),
      type: "social.capability.restored",
      title: "تمت إعادة صلاحية اجتماعية",
      body: `تمت إعادة الصلاحية: ${String(updated.capability_key || "").trim()}`,
      payload: {
        restrictionId: Number(updated.id),
        capabilityKey: String(updated.capability_key || "").trim().toLowerCase(),
        target: "social_profile",
      },
    },
  ]);

  await logAdminAudit({
    actor,
    actionKey: "admin.social.restriction.revoked",
    summary: `ألغى قيدًا اجتماعيًا #${Number(restrictionId)}`,
    targetType: "social_capability_restriction",
    targetId: Number(updated.id),
    targetLabel: String(updated.capability_key || "").trim().toLowerCase(),
    metadata: {
      userId: Number(updated.user_id),
      capabilityKey: String(updated.capability_key || "").trim().toLowerCase(),
    },
  });

  return {
    restriction: mapSocialCapabilityRestrictionItem(updated),
  };
}

function socialPenaltyBody(strikes, visibilityTier) {
  const count = Number(strikes || 0);
  if (count <= 1) {
    return "تم حذف المنشور ومَنعك من النشر لمدة يوم واحد بسبب مخالفة قواعد المجتمع.";
  }
  if (count == 2) {
    return "تم حذف المنشور ومَنعك من النشر لمدة أسبوع بسبب تكرار مخالفة قواعد المجتمع.";
  }
  if (String(visibilityTier || "").toLowerCase() === "gray_zone") {
    return "تم نقل حسابك إلى المنطقة الرصاصية. يمكنك النشر، لكن المحتوى يظهر فقط لمستخدمي المنطقة الرصاصية.";
  }
  return "تم حذف المنشور بسبب مخالفة قواعد المجتمع.";
}

export async function reviewSocialPostReport({
  postId,
  action,
  note = null,
  actor = {},
}) {
  const actorUserId = toActorUserId(actor);
  const normalizedAction = String(action || "").trim().toLowerCase();
  if (!["keep", "request_edit", "delete"].includes(normalizedAction)) {
    const err = new Error("INVALID_REPORT_ACTION");
    err.status = 400;
    throw err;
  }

  const post = await adminRepo.findPostForModeration(postId);
  if (!post) {
    const err = new Error("POST_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const reporterIds = await adminRepo.listPostReporterIds(postId);

  if (normalizedAction === "keep") {
    const increments = await adminRepo.incrementFalseReportCounts(reporterIds);
    await adminRepo.clearPostReports(postId);
    await adminRepo.insertPostReportReviewLog({
      postId,
      adminUserId: actorUserId,
      action: "keep",
      note,
    });
    await createManyNotifications(
      increments.map((row) => ({
        userId: Number(row.id),
        type: "social.report.post.dismissed",
        title: "تمت مراجعة التبليغ",
        body:
          Number(row.social_false_reports_count || 0) >= 5
            ? "تم اعتبار تبليغك كاذبًا عدة مرات، وتم إيقاف صلاحية التبليغ من حسابك."
            : `تم اعتبار التبليغ غير دقيق. عدد التبليغات الكاذبة: ${Number(
                row.social_false_reports_count || 0
              )}/5`,
        payload: {
          postId: Number(postId),
          falseReportsCount: Number(row.social_false_reports_count || 0),
          reportingBlocked: row.social_reports_blocked === true,
          target: "notifications",
        },
      }))
    );
    await logAdminAudit({
      actor,
      actionKey: "admin.social.report.keep",
      summary: `أبقى المنشور #${Number(postId)} بعد مراجعة التبليغ`,
      targetType: "social_post",
      targetId: Number(postId),
      targetLabel: post.caption ? String(post.caption).slice(0, 80) : null,
      metadata: {
        action: "keep",
        note: note || null,
        reportsCount: reporterIds.length,
      },
    });
    return { ok: true, action: "keep", postId: Number(postId) };
  }

  if (normalizedAction === "request_edit") {
    const moderationNote =
      String(note || "").trim() || "يرجى تعديل المنشور ليتوافق مع قواعد المجتمع.";
    const updated = await adminRepo.markPostPendingEdit({
      postId,
      note: moderationNote,
      adminUserId: actorUserId,
    });
    if (!updated) {
      const err = new Error("POST_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    await adminRepo.clearPostReports(postId);
    await adminRepo.insertPostReportReviewLog({
      postId,
      adminUserId: actorUserId,
      action: "request_edit",
      note: moderationNote,
    });
    await createManyNotifications([
      {
        userId: Number(post.user_id),
        type: "social.report.post.edit_requested",
        title: "مطلوب تعديل منشورك",
        body: moderationNote,
        payload: {
          postId: Number(postId),
          note: moderationNote,
          target: "social_reported_posts",
        },
      },
    ]);
    await logAdminAudit({
      actor,
      actionKey: "admin.social.report.request_edit",
      summary: `طلب تعديل المنشور #${Number(postId)}`,
      targetType: "social_post",
      targetId: Number(postId),
      targetLabel: post.caption ? String(post.caption).slice(0, 80) : null,
      metadata: {
        action: "request_edit",
        note: moderationNote,
      },
    });
    return { ok: true, action: "request_edit", postId: Number(postId) };
  }

  const deleted = await adminRepo.softDeletePostByModeration(postId);
  if (!deleted) {
    const err = new Error("POST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await adminRepo.clearPostReports(postId);
  const penalty = await adminRepo.applySocialViolationStrike(Number(post.user_id));
  await adminRepo.insertPostReportReviewLog({
    postId,
    adminUserId: actorUserId,
    action: "delete",
    note,
  });

  await createManyNotifications([
    {
      userId: Number(post.user_id),
      type: "social.report.post.deleted",
      title: "تم حذف منشورك",
      body: socialPenaltyBody(
        penalty?.strikes ?? 0,
        penalty?.social_visibility_tier || "normal"
      ),
      payload: {
        postId: Number(postId),
        strikes: Number(penalty?.strikes || 0),
        blockUntil: penalty?.social_write_block_until || null,
        visibilityTier: penalty?.social_visibility_tier || "normal",
        target:
          String(post.post_kind || "").trim().toLowerCase() === "reel"
            ? "social_reel"
            : "social_post",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.social.report.delete",
    summary: `حذف المنشور #${Number(postId)} بعد مراجعة التبليغ`,
    targetType: "social_post",
    targetId: Number(postId),
    targetLabel: post.caption ? String(post.caption).slice(0, 80) : null,
    metadata: {
      action: "delete",
      note: note || null,
      strikes: Number(penalty?.strikes || 0),
      blockUntil: penalty?.social_write_block_until || null,
      visibilityTier: penalty?.social_visibility_tier || "normal",
    },
  });

  return {
    ok: true,
    action: "delete",
    postId: Number(postId),
    strikes: Number(penalty?.strikes || 0),
    blockUntil: penalty?.social_write_block_until || null,
    visibilityTier: penalty?.social_visibility_tier || "normal",
  };
}

export async function approveEditedSocialPost({ postId, actor = {} }) {
  const post = await adminRepo.findPostForModeration(postId);
  if (!post) {
    const err = new Error("POST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const updated = await adminRepo.approveModeratedPost(postId);
  if (!updated) {
    const err = new Error("POST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await adminRepo.clearPostReports(postId);
  await adminRepo.insertPostReportReviewLog({
    postId,
    adminUserId: toActorUserId(actor),
    action: "approve_edit",
    note: null,
  });
  await createManyNotifications([
    {
      userId: Number(post.user_id),
      type: "social.report.post.edit_approved",
      title: "تم قبول التعديل",
      body: "تمت مراجعة التعديل وأعيد نشر المنشور.",
      payload: {
        postId: Number(postId),
        target:
          String(post.post_kind || "").trim().toLowerCase() === "reel"
            ? "social_reel"
            : "social_post",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.social.report.approve_edit",
    summary: `وافق على تعديل المنشور #${Number(postId)}`,
    targetType: "social_post",
    targetId: Number(postId),
    targetLabel: post.caption ? String(post.caption).slice(0, 80) : null,
    metadata: {
      action: "approve_edit",
    },
  });
  return { ok: true, postId: Number(postId), moderationStatus: "approved" };
}

export async function reviewSocialStoryReport({
  storyId,
  action,
  note = null,
  actor = {},
}) {
  const actorUserId = toActorUserId(actor);
  const normalizedAction = String(action || "").trim().toLowerCase();
  if (!["keep", "request_edit", "delete"].includes(normalizedAction)) {
    const err = new Error("INVALID_REPORT_ACTION");
    err.status = 400;
    throw err;
  }

  const story = await adminRepo.findStoryForModeration(storyId);
  if (!story) {
    const err = new Error("STORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const reporterIds = await adminRepo.listStoryReporterIds(storyId);

  if (normalizedAction === "keep") {
    const increments = await adminRepo.incrementFalseReportCounts(reporterIds);
    await adminRepo.clearStoryReports(storyId);
    await adminRepo.insertStoryReportReviewLog({
      storyId,
      adminUserId: actorUserId,
      action: "keep",
      note,
    });
    await createManyNotifications(
      increments.map((row) => ({
        userId: Number(row.id),
        type: "social.report.story.dismissed",
        title: "تمت مراجعة تبليغ الستوري",
        body:
          Number(row.social_false_reports_count || 0) >= 5
            ? "تم اعتبار تبليغك غير صحيح عدة مرات، وتم إيقاف صلاحية التبليغ من حسابك."
            : `تم اعتبار التبليغ غير دقيق. عدد التبليغات غير الصحيحة: ${Number(
                row.social_false_reports_count || 0
              )}/5`,
        payload: {
          storyId: Number(storyId),
          falseReportsCount: Number(row.social_false_reports_count || 0),
          reportingBlocked: row.social_reports_blocked === true,
          target: "notifications",
        },
      }))
    );
    await logAdminAudit({
      actor,
      actionKey: "admin.social.story_report.keep",
      summary: `أبقى الستوري #${Number(storyId)} بعد مراجعة التبليغ`,
      targetType: "social_story",
      targetId: Number(storyId),
      targetLabel: story.caption ? String(story.caption).slice(0, 80) : null,
      metadata: {
        action: "keep",
        note: note || null,
        reportsCount: reporterIds.length,
      },
    });
    return { ok: true, action: "keep", storyId: Number(storyId) };
  }

  if (normalizedAction === "request_edit") {
    const moderationNote =
      String(note || "").trim() || "يرجى تعديل الستوري ليتوافق مع قواعد المجتمع.";
    const updated = await adminRepo.markStoryPendingEdit({
      storyId,
      note: moderationNote,
      adminUserId: actorUserId,
    });
    if (!updated) {
      const err = new Error("STORY_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    await adminRepo.clearStoryReports(storyId);
    await adminRepo.insertStoryReportReviewLog({
      storyId,
      adminUserId: actorUserId,
      action: "request_edit",
      note: moderationNote,
    });
    await createManyNotifications([
      {
        userId: Number(story.user_id),
        type: "social.report.story.edit_requested",
        title: "مطلوب تعديل الستوري",
        body: moderationNote,
        payload: {
          storyId: Number(storyId),
          note: moderationNote,
          target: "social_reported_posts",
        },
      },
    ]);
    await logAdminAudit({
      actor,
      actionKey: "admin.social.story_report.request_edit",
      summary: `طلب تعديل الستوري #${Number(storyId)}`,
      targetType: "social_story",
      targetId: Number(storyId),
      targetLabel: story.caption ? String(story.caption).slice(0, 80) : null,
      metadata: {
        action: "request_edit",
        note: moderationNote,
      },
    });
    return { ok: true, action: "request_edit", storyId: Number(storyId) };
  }

  const deleted = await adminRepo.softDeleteStoryByModeration(storyId);
  if (!deleted) {
    const err = new Error("STORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await adminRepo.clearStoryReports(storyId);
  const penalty = await adminRepo.applySocialViolationStrike(Number(story.user_id));
  await adminRepo.insertStoryReportReviewLog({
    storyId,
    adminUserId: actorUserId,
    action: "delete",
    note,
  });
  await createManyNotifications([
    {
      userId: Number(story.user_id),
      type: "social.report.story.deleted",
      title: "تم حذف الستوري",
      body: socialPenaltyBody(
        penalty?.strikes ?? 0,
        penalty?.social_visibility_tier || "normal"
      ),
      payload: {
        storyId: Number(storyId),
        strikes: Number(penalty?.strikes || 0),
        blockUntil: penalty?.social_write_block_until || null,
        visibilityTier: penalty?.social_visibility_tier || "normal",
        target: "social_story",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.social.story_report.delete",
    summary: `حذف الستوري #${Number(storyId)} بعد مراجعة التبليغ`,
    targetType: "social_story",
    targetId: Number(storyId),
    targetLabel: story.caption ? String(story.caption).slice(0, 80) : null,
    metadata: {
      action: "delete",
      note: note || null,
      strikes: Number(penalty?.strikes || 0),
      blockUntil: penalty?.social_write_block_until || null,
      visibilityTier: penalty?.social_visibility_tier || "normal",
    },
  });
  return {
    ok: true,
    action: "delete",
    storyId: Number(storyId),
    strikes: Number(penalty?.strikes || 0),
    blockUntil: penalty?.social_write_block_until || null,
    visibilityTier: penalty?.social_visibility_tier || "normal",
  };
}

export async function approveEditedSocialStory({ storyId, actor = {} }) {
  const story = await adminRepo.findStoryForModeration(storyId);
  if (!story) {
    const err = new Error("STORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  const updated = await adminRepo.approveModeratedStory(storyId);
  if (!updated) {
    const err = new Error("STORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await adminRepo.clearStoryReports(storyId);
  await adminRepo.insertStoryReportReviewLog({
    storyId,
    adminUserId: toActorUserId(actor),
    action: "approve_edit",
    note: null,
  });
  await createManyNotifications([
    {
      userId: Number(story.user_id),
      type: "social.report.story.edit_approved",
      title: "تم قبول تعديل الستوري",
      body: "تمت مراجعة التعديل وإعادة نشر الستوري.",
      payload: {
        storyId: Number(storyId),
        target: "social_story",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.social.story_report.approve_edit",
    summary: `وافق على تعديل الستوري #${Number(storyId)}`,
    targetType: "social_story",
    targetId: Number(storyId),
    targetLabel: story.caption ? String(story.caption).slice(0, 80) : null,
    metadata: {
      action: "approve_edit",
    },
  });
  return { ok: true, storyId: Number(storyId), moderationStatus: "approved" };
}

export async function approveResidenceChangeRequest({
  requestId,
  reviewNote = null,
  actor = {},
}) {
  const updated = await adminRepo.approveResidenceChangeRequest({
    requestId,
    reviewedByUserId: toActorUserId(actor),
    reviewNote,
  });
  if (!updated) {
    const err = new Error("RESIDENCE_CHANGE_REQUEST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (updated.alreadyReviewed) {
    const err = new Error("RESIDENCE_CHANGE_REQUEST_ALREADY_REVIEWED");
    err.status = 409;
    throw err;
  }
  await createManyNotifications([
    {
      userId: Number(updated.user_id),
      type: "residence.change.approved",
      title: "تمت الموافقة على تعديل السكن",
      body: "تم اعتماد بيانات السكن الجديدة على حسابك.",
      payload: {
        requestId: Number(updated.id),
        target: "residence_change_request",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.residence_change.approved",
    summary: `وافق على طلب تعديل السكن #${Number(requestId)}`,
    targetType: "residence_change_request",
    targetId: Number(updated.id),
    metadata: {
      reviewNote: reviewNote || null,
      userId: Number(updated.user_id),
    },
  });
  return { request: mapResidenceChangeRequestItem(updated) };
}

export async function rejectResidenceChangeRequest({
  requestId,
  reviewNote = null,
  actor = {},
}) {
  const updated = await adminRepo.rejectResidenceChangeRequest({
    requestId,
    reviewedByUserId: toActorUserId(actor),
    reviewNote,
  });
  if (!updated) {
    const err = new Error("RESIDENCE_CHANGE_REQUEST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await createManyNotifications([
    {
      userId: Number(updated.user_id),
      type: "residence.change.rejected",
      title: "تم رفض طلب تعديل السكن",
      body: reviewNote || "يرجى مراجعة البيانات وإرسال طلب جديد إذا لزم.",
      payload: {
        requestId: Number(updated.id),
        target: "residence_change_request",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.residence_change.rejected",
    summary: `رفض طلب تعديل السكن #${Number(requestId)}`,
    targetType: "residence_change_request",
    targetId: Number(updated.id),
    metadata: {
      reviewNote: reviewNote || null,
      userId: Number(updated.user_id),
    },
  });
  return { request: mapResidenceChangeRequestItem(updated) };
}

export async function approveProfileCoreChangeRequest({
  requestId,
  reviewNote = null,
  actor = {},
}) {
  let updated;
  try {
    updated = await adminRepo.approveProfileCoreChangeRequest({
      requestId,
      reviewedByUserId: toActorUserId(actor),
      reviewNote,
    });
  } catch (error) {
    if (String(error?.code || "").trim().toUpperCase() === "USERNAME_TAKEN") {
      const err = new Error("USERNAME_TAKEN");
      err.status = 409;
      throw err;
    }
    throw error;
  }
  if (!updated) {
    const err = new Error("PROFILE_CORE_CHANGE_REQUEST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  if (updated.alreadyReviewed) {
    const err = new Error("PROFILE_CORE_CHANGE_REQUEST_ALREADY_REVIEWED");
    err.status = 409;
    throw err;
  }
  await createManyNotifications([
    {
      userId: Number(updated.user_id),
      type: "profile.change.approved",
      title: "تمت الموافقة على تعديل البيانات الأساسية",
      body: "تم اعتماد تحديث الاسم أو اسم المستخدم في حسابك.",
      payload: {
        requestId: Number(updated.id),
        target: "profile_core_change_request",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.profile_core_change.approved",
    summary: `وافق على طلب تعديل بيانات أساسية #${Number(requestId)}`,
    targetType: "profile_core_change_request",
    targetId: Number(updated.id),
    metadata: {
      reviewNote: reviewNote || null,
      userId: Number(updated.user_id),
    },
  });
  return { request: mapProfileCoreChangeRequestItem(updated) };
}

export async function rejectProfileCoreChangeRequest({
  requestId,
  reviewNote = null,
  actor = {},
}) {
  const updated = await adminRepo.rejectProfileCoreChangeRequest({
    requestId,
    reviewedByUserId: toActorUserId(actor),
    reviewNote,
  });
  if (!updated) {
    const err = new Error("PROFILE_CORE_CHANGE_REQUEST_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  await createManyNotifications([
    {
      userId: Number(updated.user_id),
      type: "profile.change.rejected",
      title: "تم رفض طلب تعديل البيانات الأساسية",
      body: reviewNote || "يرجى تعديل البيانات وإعادة الإرسال.",
      payload: {
        requestId: Number(updated.id),
        target: "profile_core_change_request",
      },
    },
  ]);
  await logAdminAudit({
    actor,
    actionKey: "admin.profile_core_change.rejected",
    summary: `رفض طلب تعديل بيانات أساسية #${Number(requestId)}`,
    targetType: "profile_core_change_request",
    targetId: Number(updated.id),
    metadata: {
      reviewNote: reviewNote || null,
      userId: Number(updated.user_id),
    },
  });
  return { request: mapProfileCoreChangeRequestItem(updated) };
}



