import { q } from "../../config/db.js";
import { checkPermission } from "../security/permissions.service.js";

function uniquePositiveIds(values = []) {
  const seen = new Set();
  const ids = [];
  for (const value of values) {
    const id = Number(value);
    if (!Number.isInteger(id) || id <= 0 || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

export async function listBackofficeNotificationUserIds({
  permissionKey,
  limit = 500,
} = {}) {
  const safeLimit = Math.max(1, Math.min(1000, Number(limit) || 500));
  const result = await q(
    `SELECT DISTINCT id
     FROM app_user
     WHERE COALESCE(is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(is_super_admin, FALSE) = TRUE
         OR LOWER(COALESCE(role::text, '')) IN ('admin', 'deputy_admin', 'staff')
       )
     ORDER BY id ASC
     LIMIT $1`,
    [safeLimit],
  );

  const candidateIds = uniquePositiveIds(result.rows.map((row) => row.id));
  const key = String(permissionKey || "").trim();
  if (!key) return candidateIds;

  const checks = await Promise.all(
    candidateIds.map(async (userId) => {
      try {
        const access = await checkPermission(userId, key, "own");
        return access?.allowed ? userId : null;
      } catch {
        return null;
      }
    }),
  );
  return checks.filter((id) => Number.isInteger(id) && id > 0);
}

export function buildAdminOrderCreatedNotifications({
  recipientUserIds,
  order,
  merchantName = null,
  orderGroupId = null,
  storesCount = null,
} = {}) {
  const orderId = Number(order?.id ?? order?.orderId ?? 0);
  const merchantId = Number(order?.merchant_id ?? order?.merchantId ?? 0);
  if (!Number.isInteger(orderId) || orderId <= 0) return [];

  const resolvedMerchantName = String(
    merchantName ?? order?.merchant_name ?? order?.merchantName ?? "",
  ).trim();
  const status = String(order?.status || "pending").trim().toLowerCase();
  const groupId = Number(orderGroupId ?? order?.order_group_id ?? order?.orderGroupId ?? 0);
  const normalizedStoresCount = Number(storesCount ?? 0);
  const target = "admin_order_details";

  return uniquePositiveIds(recipientUserIds).map((userId) => ({
    userId,
    type: "admin_order_created",
    title: "طلب متجر جديد",
    body: resolvedMerchantName
      ? `طلب جديد رقم #${orderId} لدى ${resolvedMerchantName}`
      : `طلب جديد رقم #${orderId}`,
    orderId,
    merchantId: merchantId > 0 ? merchantId : undefined,
    payload: {
      target,
      targetModule: "admin",
      target_module: "admin",
      roleScope: "admin",
      role_scope: "admin",
      action: "open_admin_order",
      targetEntity: "order",
      target_entity: "order",
      entityId: orderId,
      entity_id: orderId,
      orderId,
      merchantId: merchantId > 0 ? merchantId : null,
      merchantName: resolvedMerchantName || null,
      status,
      orderGroupId: groupId > 0 ? groupId : null,
      storesCount:
        Number.isInteger(normalizedStoresCount) && normalizedStoresCount > 0
          ? normalizedStoresCount
          : null,
      requiresAction: true,
      notificationType: "admin_order_created",
      notification_type: "admin_order_created",
    },
  }));
}

export function buildAdminTaxiRideRequestedNotifications({
  recipientUserIds,
  ride,
} = {}) {
  const rideId = Number(ride?.id ?? ride?.rideId ?? 0);
  if (!Number.isInteger(rideId) || rideId <= 0) return [];

  const pickupLabel = String(ride?.pickup?.label ?? ride?.pickupLabel ?? "").trim();
  const destinationLabel = String(
    ride?.dropoff?.label ?? ride?.destinationLabel ?? ride?.dropoffLabel ?? "",
  ).trim();
  const proposedFareIqd = Number(ride?.proposedFareIqd ?? ride?.proposed_fare_iqd ?? 0);
  const status = String(ride?.status || "searching").trim().toLowerCase();
  const customerUserId = Number(ride?.customerUserId ?? ride?.customer_user_id ?? 0);
  const target = "admin_taxi_ride_details";

  return uniquePositiveIds(recipientUserIds).map((userId) => ({
    userId,
    type: "admin_taxi_ride_requested",
    title: "رحلة تكسي جديدة",
    body:
      pickupLabel && destinationLabel
        ? `رحلة #${rideId} من ${pickupLabel} إلى ${destinationLabel}`
        : `رحلة تكسي جديدة رقم #${rideId}`,
    payload: {
      target,
      targetModule: "admin",
      target_module: "admin",
      roleScope: "admin",
      role_scope: "admin",
      action: "open_admin_taxi_ride",
      targetEntity: "taxi_ride",
      target_entity: "taxi_ride",
      entityId: rideId,
      entity_id: rideId,
      rideId,
      pickupLabel: pickupLabel || null,
      destinationLabel: destinationLabel || null,
      proposedFareIqd: Number.isFinite(proposedFareIqd) ? proposedFareIqd : null,
      customerUserId:
        Number.isInteger(customerUserId) && customerUserId > 0
          ? customerUserId
          : null,
      status,
      requiresAction: true,
      notificationType: "admin_taxi_ride_requested",
      notification_type: "admin_taxi_ride_requested",
    },
  }));
}
