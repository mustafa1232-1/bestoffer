import { hashPin } from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import * as analyticsRepo from "../analytics/analytics.repo.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";

function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    role: u.role,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
    imageUrl: u.image_url,
  };
}

export async function registerDelivery(dto) {
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
    role: "delivery",
  });

  const token = signAccessToken({
    id: user.id,
    role: user.role || "delivery",
  });

  return {
    token,
    user: mapUser(user),
  };
}

export async function currentOrders(deliveryUserId) {
  return ordersRepo.listDeliveryCurrentOrders(deliveryUserId);
}

export async function history(deliveryUserId, date) {
  return ordersRepo.listDeliveryHistory(deliveryUserId, date || null);
}

export async function claimOrder(deliveryUserId, orderId) {
  const ok = await ordersRepo.claimDeliveryOrder(deliveryUserId, Number(orderId));
  if (!ok) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
}

export async function startOrder(deliveryUserId, orderId, estimatedDeliveryMinutes) {
  const fixedEtaMaxMinutes = 10;
  const ok = await ordersRepo.markOrderOnTheWay(
    deliveryUserId,
    Number(orderId),
    fixedEtaMaxMinutes
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
}

export async function markDelivered(deliveryUserId, orderId) {
  const ok = await ordersRepo.markOrderDelivered(deliveryUserId, Number(orderId));
  if (!ok) {
    const err = new Error("ORDER_NOT_AVAILABLE");
    err.status = 404;
    throw err;
  }
}

export async function endDay(deliveryUserId, date) {
  return ordersRepo.endDeliveryDay(deliveryUserId, date || null);
}

export async function analytics(deliveryUserId) {
  return analyticsRepo.getDeliveryAnalytics(deliveryUserId);
}
