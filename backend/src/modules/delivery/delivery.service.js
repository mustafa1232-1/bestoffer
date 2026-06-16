import { hashPin } from "../../shared/utils/hash.js";
import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";
import * as analyticsRepo from "../../shared/analytics/commerce-analytics.repo.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import { runWithGeneratedAppUserUsername } from "../auth/auth.service.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import { invalidateOrderListCacheForUser } from "../orders/orders.service.js";
import * as repo from "./delivery.repo.js";

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

export async function registerDelivery(dto) {
  const address = assertValidBasmayaAddress({
    block: dto.block,
    buildingNumber: dto.buildingNumber,
    apartment: dto.apartment,
  });
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

  const exists = await findUserByPhone(dto.phone.trim());
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const fullName = dto.fullName.trim();
  const phone = dto.phone.trim();
  const pinHash = await hashPin(dto.pin);

  let user = null;
  try {
    user = await runWithGeneratedAppUserUsername({
      fullName,
      phone,
      execute: (username) =>
        createUser({
          fullName,
          username,
          phone,
          pinHash,
          block: address.block,
          buildingNumber: address.buildingNumber,
          apartment: address.apartment,
          imageUrl: dto.profileImageUrl || dto.imageUrl || null,
          role: "taxi_captain",
          analyticsConsentGranted: true,
          analyticsConsentVersion,
          analyticsConsentGrantedAt: new Date(),
          chatQualityReviewConsent: true,
        }),
    });

    await repo.setDeliveryAccountPendingApproval(Number(user.id));
    await repo.createDeliveryCaptainProfile({
      userId: Number(user.id),
      profileImageUrl: dto.profileImageUrl || dto.imageUrl || null,
      carImageUrl: dto.carImageUrl || null,
      vehicleType: dto.vehicleType || "sedan",
      carMake: dto.carMake,
      carModel: dto.carModel,
      carYear: dto.carYear,
      carColor: dto.carColor,
      plateNumber: dto.plateNumber,
    });
  } catch (error) {
    if (user?.id) {
      await repo.deleteUserById(Number(user.id)).catch(() => {});
    }
    throw error;
  }

  const approvers = await repo.listDeliveryApproverUserIds();
  await createManyNotifications(
    approvers.map((approverId) => ({
      userId: Number(approverId),
      type: "admin_delivery_pending_approval",
      title: "حساب كابتن بانتظار الموافقة",
      body: `يوجد طلب كابتن جديد: ${dto.fullName.trim()} (${dto.phone.trim()})`,
      payload: {
        captainUserId: Number(user.id),
      },
    }))
  );

  return {
    pendingApproval: true,
    message: "DELIVERY_ACCOUNT_PENDING_APPROVAL",
    user: {
      id: Number(user.id),
      fullName: user.full_name,
      phone: user.phone,
      role: user.role,
      isTaxiCaptain: true,
      deliveryAccountApproved: false,
    },
  };
}

export async function currentOrders(deliveryUserId) {
  return ordersRepo.listDeliveryCurrentOrders(deliveryUserId);
}

export async function history(deliveryUserId, date) {
  return ordersRepo.listDeliveryHistory(deliveryUserId, date || null);
}

export async function claimOrder(deliveryUserId, orderId) {
  const updated = await ordersRepo.claimDeliveryOrder(
    deliveryUserId,
    Number(orderId),
    10
  );
  if (!updated) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

export async function startOrder(deliveryUserId, orderId) {
  const updated = await ordersRepo.markOrderArrived(deliveryUserId, Number(orderId));
  if (!updated) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

export async function markArrived(deliveryUserId, orderId) {
  const updated = await ordersRepo.markOrderArrived(deliveryUserId, Number(orderId));
  if (!updated) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

export async function markDelivered(deliveryUserId, orderId) {
  const updated = await ordersRepo.markOrderDelivered(deliveryUserId, Number(orderId));
  if (!updated) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
  invalidateOrderListCacheForUser(updated.customer_user_id);
}

export async function endDay(deliveryUserId, date) {
  return ordersRepo.endDeliveryDay(deliveryUserId, date || null);
}

export async function analytics(deliveryUserId) {
  return analyticsRepo.getDeliveryAnalytics(deliveryUserId);
}
