import { hashPin } from "../../shared/utils/hash.js";
import { q } from "../../config/db.js";
import * as analyticsRepo from "../analytics/analytics.repo.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

export async function registerDelivery(dto) {
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

  const pinHash = await hashPin(dto.pin);

  const user = await createUser({
    fullName: dto.fullName.trim(),
    phone: dto.phone.trim(),
    pinHash,
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    imageUrl: dto.profileImageUrl || dto.imageUrl || null,
    role: "delivery",
    analyticsConsentGranted: true,
    analyticsConsentVersion,
    analyticsConsentGrantedAt: new Date(),
  });

  await q(
    `UPDATE app_user
     SET delivery_account_approved = FALSE,
         delivery_approved_by_user_id = NULL,
         delivery_approved_at = NULL
     WHERE id = $1`,
    [Number(user.id)]
  );

  await q(
    `INSERT INTO taxi_captain_profile
      (
        user_id,
        profile_image_url,
        car_image_url,
        vehicle_type,
        car_make,
        car_model,
        car_year,
        car_color,
        plate_number,
        is_active,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET
       profile_image_url = EXCLUDED.profile_image_url,
       car_image_url = EXCLUDED.car_image_url,
       vehicle_type = EXCLUDED.vehicle_type,
       car_make = EXCLUDED.car_make,
       car_model = EXCLUDED.car_model,
       car_year = EXCLUDED.car_year,
       car_color = EXCLUDED.car_color,
       plate_number = EXCLUDED.plate_number,
       is_active = TRUE,
       updated_at = NOW()`,
    [
      Number(user.id),
      dto.profileImageUrl || null,
      dto.carImageUrl || null,
      String(dto.vehicleType || "").trim().toLowerCase(),
      String(dto.carMake || "").trim(),
      String(dto.carModel || "").trim(),
      Number(dto.carYear),
      dto.carColor ? String(dto.carColor).trim() : null,
      String(dto.plateNumber || "").trim().toUpperCase(),
    ]
  );

  const approversResult = await q(
    `SELECT DISTINCT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')
        OR is_super_admin = TRUE`
  );

  await createManyNotifications(
    approversResult.rows.map((row) => ({
      userId: Number(row.id),
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
