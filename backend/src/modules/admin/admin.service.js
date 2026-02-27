import { hashPin } from "../../shared/utils/hash.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import * as analyticsRepo from "../analytics/analytics.repo.js";
import * as behaviorService from "../behavior/behavior.service.js";
import * as ordersRepo from "../orders/orders.repo.js";
import * as adminRepo from "./admin.repo.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

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

export async function createManagedUser(dto, actor = {}) {
  const requesterId = Number(actor.id || 0);
  const requesterIsSuperAdmin =
    actor.isSuperAdmin === true ||
    (requesterId > 0 && (await adminRepo.isUserSuperAdmin(requesterId)));
  if (dto.role === "admin" && !requesterIsSuperAdmin) {
    const err = new Error("FORBIDDEN_SUPER_ADMIN_ONLY");
    err.status = 403;
    throw err;
  }

  const exists = await findUserByPhone(dto.phone.trim());
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(dto.pin);
  const user = await createUser({
    fullName: dto.fullName.trim(),
    phone: dto.phone.trim(),
    pinHash,
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    imageUrl: dto.imageUrl || null,
    role: dto.role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "admin_created_v1",
    analyticsConsentGrantedAt: new Date(),
  });

  return mapUser(user);
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

export async function approveMerchant(merchantId, adminUserId) {
  const ok = await analyticsRepo.approveMerchant(Number(merchantId), Number(adminUserId));
  if (!ok) {
    const err = new Error("MERCHANT_NOT_FOUND_OR_ALREADY_APPROVED");
    err.status = 404;
    throw err;
  }
}

export async function getPendingSettlements() {
  return analyticsRepo.listPendingSettlements();
}

export async function approveSettlement(settlementId, adminUserId, adminNote) {
  const ok = await analyticsRepo.approveSettlement(
    Number(settlementId),
    Number(adminUserId),
    adminNote?.trim()
  );
  if (!ok) {
    const err = new Error("SETTLEMENT_NOT_FOUND_OR_ALREADY_PROCESSED");
    err.status = 404;
    throw err;
  }
}

function mapManagedMerchant(m) {
  return {
    id: m.id,
    name: m.name,
    type: m.type,
    phone: m.phone,
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
              ? `تم تعطيل متجر ${row.name} مؤقتًا من الإدارة`
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

  return {
    id: row.id,
    name: row.name,
    isDisabled: row.is_disabled,
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

export async function approveDeliveryAccount(deliveryUserId, adminUserId) {
  const approved = await adminRepo.approveDeliveryAccount(
    Number(deliveryUserId),
    Number(adminUserId)
  );

  if (!approved) {
    const err = new Error("DELIVERY_ACCOUNT_NOT_FOUND_OR_ALREADY_APPROVED");
    err.status = 404;
    throw err;
  }

  await createManyNotifications([
    {
      userId: Number(approved.id),
      type: "delivery_account_approved",
      title: "تمت الموافقة على حسابك",
      body: "تمت مراجعة بياناتك ويمكنك الآن تسجيل الدخول ككابتن.",
      payload: {
        deliveryUserId: Number(approved.id),
      },
    },
  ]);

  return {
    id: Number(approved.id),
    fullName: approved.full_name,
    phone: approved.phone,
  };
}

export async function printOrdersReport(period) {
  const normalizedPeriod = String(period || "day").toLowerCase();
  return ordersRepo.listAdminOrdersForReport(normalizedPeriod);
}

export async function listCustomerInsights(query) {
  return behaviorService.listCustomersInsight(query || {});
}

export async function getCustomerInsightDetails(customerUserId) {
  return behaviorService.getCustomerFullInsight(Number(customerUserId));
}
