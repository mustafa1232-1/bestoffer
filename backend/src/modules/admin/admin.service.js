import { hashPin } from "../../shared/utils/hash.js";
import { createUser, findUserByPhone } from "../auth/auth.repo.js";
import * as analyticsRepo from "../analytics/analytics.repo.js";
import * as behaviorService from "../behavior/behavior.service.js";
import * as ordersRepo from "../orders/orders.repo.js";
import * as taxiService from "../taxi/taxi.service.js";
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
    adminUserId: Number(adminUserId),
    cycleDays: Number(cycleDays) || 30,
  });
  const subscription = result.subscription || {};
  return {
    ...result,
    credits: {
      packagePriceIqd: Number(subscription.packagePriceIqd || 10000),
      packageRideCount: Number(subscription.packageRideLimit || 15),
      used: Number(subscription.usedRides || 0),
      remaining: Number(subscription.remainingRides || 0),
      status: Number(subscription.remainingRides || 0) <= 0
        ? "exhausted"
        : Number(subscription.remainingRides || 0) === 1
          ? "near_exhaustion"
          : "active",
      cashPaymentPending: subscription.cashPaymentPending === true,
    },
  };
}

export async function setTaxiCaptainDiscount({
  captainUserId,
  discountPercent,
  adminUserId,
}) {
  return taxiService.setCaptainDiscountByAdmin({
    captainUserId: Number(captainUserId),
    discountPercent: Number(discountPercent),
    adminUserId: Number(adminUserId),
  });
}

function mapTaxiCredit(row) {
  const purchased = Number(row.purchased_ride_credits ?? 15);
  const used = Number(row.consumed_ride_credits ?? 0);
  const remaining = Math.max(0, purchased - used);
  return {
    packagePriceIqd: Number(row.package_price_iqd ?? 10000),
    packageRideCount: Number(row.package_ride_count ?? 15),
    purchased,
    used,
    remaining,
    status: remaining <= 0 ? "exhausted" : remaining === 1 ? "near_exhaustion" : "active",
    cashPaymentPending: row.cash_payment_pending === true,
    cashPaymentRequestedAt: row.cash_payment_requested_at || null,
    lastPaymentConfirmedAt: row.last_cash_payment_confirmed_at || null,
  };
}

export async function getTaxiAdminOverview(query) {
  const data = await adminRepo.getTaxiAdminOverview(query);
  const s = data.summary || {};
  return {
    summary: {
      rides: {
        total: Number(s.rides_total || 0),
        active: Number(s.rides_active || 0),
        searching: Number(s.rides_searching || 0),
        captainAssigned: Number(s.rides_captain_assigned || 0),
        captainArriving: Number(s.rides_captain_arriving || 0),
        rideStarted: Number(s.rides_started || 0),
        completed: Number(s.rides_completed || 0),
        cancelled: Number(s.rides_cancelled || 0),
        expired: Number(s.rides_expired || 0),
      },
      captains: {
        total: Number(s.captains_total || 0),
        online: Number(s.captains_online || 0),
        nearExhaustion: Number(s.captains_near_exhaustion || 0),
        exhausted: Number(s.captains_exhausted || 0),
        paymentPending: Number(s.captains_payment_pending || 0),
      },
      credits: { packagePriceIqd: 10000, packageRideCount: 15 },
    },
    rides: data.rides.map((r) => ({
      id: Number(r.id), status: r.status,
      customer: { id: Number(r.customer_user_id), fullName: r.customer_full_name, phone: r.customer_phone || null },
      captain: r.assigned_captain_user_id ? { id: Number(r.assigned_captain_user_id), fullName: r.captain_full_name, phone: r.captain_phone || null } : null,
      pickup: { label: r.pickup_label, latitude: Number(r.pickup_latitude), longitude: Number(r.pickup_longitude) },
      dropoff: { label: r.dropoff_label, latitude: Number(r.dropoff_latitude), longitude: Number(r.dropoff_longitude) },
      proposedFareIqd: Number(r.proposed_fare_iqd), agreedFareIqd: r.agreed_fare_iqd == null ? null : Number(r.agreed_fare_iqd),
      createdAt: r.created_at, updatedAt: r.updated_at, startedAt: r.started_at || null,
      completedAt: r.completed_at || null, cancelledAt: r.cancelled_at || null,
    })),
    captains: data.captains.map((r) => ({
      id: Number(r.id), fullName: r.full_name, phone: r.phone || null,
      approved: r.delivery_account_approved === true, online: r.is_online === true,
      lastSeenAt: r.last_seen_at || null,
      vehicle: { type: r.vehicle_type || null, make: r.car_make || null, model: r.car_model || null,
        year: r.car_year == null ? null : Number(r.car_year), color: r.car_color || null,
        plateNumber: r.plate_number || null, profileImageUrl: r.profile_image_url || null, carImageUrl: r.car_image_url || null },
      credits: mapTaxiCredit(r),
      rides: { total: Number(r.rides_total || 0), completed: Number(r.rides_completed || 0),
        active: Number(r.rides_active || 0), cancelled: Number(r.rides_cancelled || 0) },
    })),
    pagination: { limit: query.limit, offset: query.offset, ridesReturned: data.rides.length, captainsReturned: data.captains.length },
  };
}

export async function adminCancelTaxiRide({ rideId, adminUserId, reason }) {
  const result = await adminRepo.adminCancelTaxiRide({ rideId, adminUserId, reason });
  if (result.code === "NOT_FOUND") {
    const err = new Error("TAXI_RIDE_NOT_FOUND"); err.status = 404; throw err;
  }
  if (result.code === "ALREADY_CLOSED") {
    const err = new Error("TAXI_RIDE_ALREADY_CLOSED"); err.status = 409; throw err;
  }
  const recipients = [result.ride.customer_user_id, result.ride.assigned_captain_user_id].filter(Boolean);
  await createManyNotifications(recipients.map((userId) => ({
    userId: Number(userId), type: "taxi.ride.cancelled_by_admin", title: "ألغت الإدارة الرحلة",
    body: `تم إلغاء الرحلة من الإدارة. السبب: ${reason}`,
    payload: { rideId: Number(result.ride.id), reason, cancelledByUserId: Number(adminUserId) },
  })));
  return { ride: { id: Number(result.ride.id), status: result.ride.status, cancelledAt: result.ride.cancelled_at },
    reason, cancelledByUserId: Number(adminUserId), previousStatus: result.previousStatus };
}

export async function adjustTaxiCaptainCredits({ captainUserId, adminUserId, delta, reason }) {
  const captain = await adminRepo.findTaxiCaptainById(Number(captainUserId));
  if (!captain) { const err = new Error("TAXI_CAPTAIN_NOT_FOUND"); err.status = 404; throw err; }
  const row = await adminRepo.adjustCaptainRideCredits({ captainUserId, adminUserId, delta, reason });
  if (!row) { const err = new Error("TAXI_CREDIT_ADJUSTMENT_EXCEEDS_BALANCE"); err.status = 409; throw err; }
  await createManyNotifications([{ userId: Number(captainUserId), type: "taxi.captain.credits.adjusted",
    title: "تم تعديل رصيد رحلاتك", body: `${reason} (${delta > 0 ? "+" : ""}${delta} رحلة)`,
    payload: { delta, reason, remaining: Number(row.purchased_ride_credits) - Number(row.consumed_ride_credits) } }]);
  return { captainUserId: Number(captainUserId), credits: mapTaxiCredit(row) };
}

function mapAdBoardItem(row) {
  return {
    id: Number(row.id),
    title: row.title,
    subtitle: row.subtitle,
    imageUrl: row.image_url,
    badgeLabel: row.badge_label,
    ctaLabel: row.cta_label,
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

export async function listAdBoardItems() {
  const rows = await adminRepo.listAdBoardItems();
  return rows.map(mapAdBoardItem);
}

export async function createAdBoardItem(dto, adminUserId) {
  await assertMerchantExists(dto.merchantId);
  const created = await adminRepo.createAdBoardItem({
    ...dto,
    actorUserId: Number(adminUserId),
  });
  return mapAdBoardItem(created);
}

export async function updateAdBoardItem(itemId, dto, adminUserId) {
  if (Object.prototype.hasOwnProperty.call(dto, "merchantId")) {
    await assertMerchantExists(dto.merchantId);
  }
  const updated = await adminRepo.updateAdBoardItem(itemId, dto, adminUserId);
  if (!updated) {
    const err = new Error("AD_BOARD_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return mapAdBoardItem(updated);
}

export async function deleteAdBoardItem(itemId) {
  const deleted = await adminRepo.deleteAdBoardItem(itemId);
  if (!deleted) {
    const err = new Error("AD_BOARD_ITEM_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return { id: Number(deleted.id) };
}
