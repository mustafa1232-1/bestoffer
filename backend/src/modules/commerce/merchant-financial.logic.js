import { q } from "../../config/db.js";

const DEFAULT_MERCHANT_BILLING_PROFILE = Object.freeze({
  commissionType: "percentage",
  commissionValue: 10,
  serviceFeeType: "fixed",
  serviceFeeValue: 250,
  deliveryFeeMode: "dynamic",
  appDeliveryFeeValue: 1000,
  storeDeliveryFeeValue: 0,
  appDeliveryEnabled: true,
  merchantDeliveryEnabled: true,
  settlementCycle: "weekly",
  distributionPolicy: "commission_service_delivery",
  gracePeriodDays: 0,
  profileVersion: 1,
});

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundMoney(value) {
  return Math.round((toNumber(value, 0) + Number.EPSILON) * 100) / 100;
}

function normalizeJsonObject(value) {
  if (!value) return null;
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? parsed
        : null;
    } catch {
      return null;
    }
  }
  if (typeof value === "object" && !Array.isArray(value)) return value;
  return null;
}

export function normalizeCommissionType(value) {
  const normalized = String(value || "percentage").trim().toLowerCase();
  return normalized === "fixed" ? "fixed" : "percentage";
}

export function normalizeServiceFeeType(value) {
  const normalized = String(value || "fixed").trim().toLowerCase();
  if (["percentage", "per_order", "global_rule"].includes(normalized)) {
    return normalized;
  }
  return "fixed";
}

export function normalizeDeliveryFeeMode(value) {
  const normalized = String(value || "dynamic").trim().toLowerCase();
  if (["app_defined", "store_defined", "dynamic"].includes(normalized)) {
    return normalized;
  }
  if (normalized === "fixed" || normalized === "percentage") {
    return "dynamic";
  }
  return "dynamic";
}

export function normalizeApprovalStatus(value) {
  const normalized = String(value || "pending_admin_review").trim().toLowerCase();
  if (
    [
      "pending_admin_review",
      "awaiting_store_financial_acceptance",
      "approved",
      "rejected",
    ].includes(normalized)
  ) {
    return normalized;
  }
  return "pending_admin_review";
}

export function normalizeMerchantBillingProfile(row = {}) {
  const hasRow = row && typeof row === "object" && Object.keys(row).length > 0;
  const legacyRate = toNumber(
    row.commission_rate,
    DEFAULT_MERCHANT_BILLING_PROFILE.commissionValue / 100
  );
  const commissionType = normalizeCommissionType(
    row.commission_type ?? DEFAULT_MERCHANT_BILLING_PROFILE.commissionType
  );
  const commissionValue = roundMoney(
    row.commission_value != null
      ? row.commission_value
      : commissionType === "percentage"
      ? legacyRate * 100
      : DEFAULT_MERCHANT_BILLING_PROFILE.commissionValue
  );
  const serviceFeeType = normalizeServiceFeeType(
    row.service_fee_type ??
      row.service_fee_mode ??
      DEFAULT_MERCHANT_BILLING_PROFILE.serviceFeeType
  );
  const serviceFeeValue = roundMoney(
    row.service_fee_value != null
      ? row.service_fee_value
      : DEFAULT_MERCHANT_BILLING_PROFILE.serviceFeeValue
  );
  const deliveryFeeMode = normalizeDeliveryFeeMode(
    row.delivery_fee_mode ?? DEFAULT_MERCHANT_BILLING_PROFILE.deliveryFeeMode
  );
  const appDeliveryFeeValue = roundMoney(
    row.app_delivery_fee_value != null
      ? row.app_delivery_fee_value
      : row.delivery_fee_value != null
      ? row.delivery_fee_value
      : DEFAULT_MERCHANT_BILLING_PROFILE.appDeliveryFeeValue
  );
  const storeDeliveryFeeValue = roundMoney(
    row.store_delivery_fee_value != null
      ? row.store_delivery_fee_value
      : row.delivery_fee_value != null
      ? row.delivery_fee_value
      : DEFAULT_MERCHANT_BILLING_PROFILE.storeDeliveryFeeValue
  );

  return {
    merchantId: Number(row.merchant_id || row.merchantId || 0) || null,
    commissionType,
    commissionValue,
    commissionRate:
      commissionType === "percentage"
        ? roundMoney(commissionValue / 100)
        : roundMoney(legacyRate),
    serviceFeeType,
    serviceFeeValue,
    deliveryFeeMode,
    appDeliveryFeeValue,
    storeDeliveryFeeValue,
    appDeliveryEnabled:
      row.app_delivery_enabled == null
        ? DEFAULT_MERCHANT_BILLING_PROFILE.appDeliveryEnabled
        : row.app_delivery_enabled !== false,
    merchantDeliveryEnabled:
      row.merchant_delivery_enabled == null
        ? DEFAULT_MERCHANT_BILLING_PROFILE.merchantDeliveryEnabled
        : row.merchant_delivery_enabled !== false,
    settlementCycle: String(
      row.settlement_cycle || DEFAULT_MERCHANT_BILLING_PROFILE.settlementCycle
    )
      .trim()
      .toLowerCase(),
    distributionPolicy: String(
      row.distribution_policy ||
        DEFAULT_MERCHANT_BILLING_PROFILE.distributionPolicy
    )
      .trim()
      .toLowerCase(),
    gracePeriodDays: Math.max(
      0,
      Number(
        row.grace_period_days ?? DEFAULT_MERCHANT_BILLING_PROFILE.gracePeriodDays
      ) || 0
    ),
    profileVersion: Math.max(
      1,
      Number(row.profile_version || DEFAULT_MERCHANT_BILLING_PROFILE.profileVersion) ||
        DEFAULT_MERCHANT_BILLING_PROFILE.profileVersion
    ),
    effectiveFrom:
      row.effective_from || row.updated_at || row.created_at || new Date().toISOString(),
    updatedAt: row.updated_at || row.created_at || null,
    updatedByUserId: Number(row.updated_by_user_id || 0) || null,
    raw: hasRow ? row : { ...DEFAULT_MERCHANT_BILLING_PROFILE, merchant_id: row.merchant_id || row.merchantId || null },
  };
}

export async function getMerchantBillingProfile(merchantId) {
  const result = await q(
    `SELECT *
     FROM merchant_billing_profile
     WHERE merchant_id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return normalizeMerchantBillingProfile(result.rows[0] || { merchant_id: merchantId });
}

function resolveServiceFeeAmount(subtotal, explicitServiceFee, profile) {
  if (explicitServiceFee > 0) return explicitServiceFee;
  if (subtotal <= 0) return 0;
  const value = roundMoney(profile.serviceFeeValue);
  if (value <= 0) return 0;
  if (profile.serviceFeeType === "percentage") {
    return roundMoney((subtotal * value) / 100);
  }
  return value;
}

function resolveCommissionAmount(subtotal, profile) {
  const value = roundMoney(profile.commissionValue);
  if (value <= 0 || subtotal <= 0) return 0;
  if (profile.commissionType === "fixed") {
    return value;
  }
  return roundMoney((subtotal * value) / 100);
}

function resolveDeliveryBreakdown({
  order,
  profile,
  explicitDeliveryFee,
  subtotal,
}) {
  const courierSource = String(
    order?.courier_source || (order?.is_merchant_delivery === true ? "merchant" : "app")
  )
    .trim()
    .toLowerCase();
  const deliveryType = String(order?.delivery_type || "delivery").trim().toLowerCase();

  if (deliveryType === "pickup" || courierSource === "none") {
    return {
      courierSource,
      deliveryType,
      deliveryFee: 0,
      appDeliveryFeeAmount: 0,
      storeDeliveryFeeAmount: 0,
    };
  }

  if (order?.has_free_delivery === true || order?.free_delivery_override === true) {
    return {
      courierSource,
      deliveryType,
      deliveryFee: 0,
      appDeliveryFeeAmount: 0,
      storeDeliveryFeeAmount: 0,
    };
  }

  const baseAppDelivery =
    explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : roundMoney(profile.appDeliveryFeeValue);
  const baseStoreDelivery =
    explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : roundMoney(profile.storeDeliveryFeeValue || profile.appDeliveryFeeValue);

  let appDeliveryFeeAmount = 0;
  let storeDeliveryFeeAmount = 0;

  switch (profile.deliveryFeeMode) {
    case "store_defined":
      storeDeliveryFeeAmount = courierSource === "merchant" || courierSource === "app"
        ? baseStoreDelivery
        : 0;
      break;
    case "app_defined":
      if (courierSource === "app" && profile.appDeliveryEnabled) {
        appDeliveryFeeAmount = baseAppDelivery;
      } else if (courierSource === "merchant" && profile.merchantDeliveryEnabled) {
        storeDeliveryFeeAmount = baseStoreDelivery;
      }
      break;
    case "dynamic":
    default:
      if (courierSource === "app" && profile.appDeliveryEnabled) {
        appDeliveryFeeAmount = baseAppDelivery;
      } else if (courierSource === "merchant" && profile.merchantDeliveryEnabled) {
        storeDeliveryFeeAmount = baseStoreDelivery;
      }
      break;
  }

  const deliveryFee = roundMoney(
    appDeliveryFeeAmount > 0
      ? appDeliveryFeeAmount
      : storeDeliveryFeeAmount > 0
      ? storeDeliveryFeeAmount
      : explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : 0
  );

  return {
    courierSource,
    deliveryType,
    deliveryFee,
    appDeliveryFeeAmount: roundMoney(appDeliveryFeeAmount),
    storeDeliveryFeeAmount: roundMoney(storeDeliveryFeeAmount),
  };
}

export function computeOrderFinancialSnapshot(order, profileInput = {}) {
  const profile = normalizeMerchantBillingProfile(profileInput);
  const snapshotSource = normalizeJsonObject(order?.financial_config_snapshot_json);
  if (snapshotSource?.appReceivableAmount != null) {
    return {
      ...snapshotSource,
      profileVersion: Math.max(1, Number(snapshotSource.profileVersion || profile.profileVersion) || 1),
      commissionAmount: roundMoney(snapshotSource.commissionAmount),
      serviceFeeAmount: roundMoney(snapshotSource.serviceFeeAmount),
      appDeliveryFeeAmount: roundMoney(snapshotSource.appDeliveryFeeAmount),
      storeDeliveryFeeAmount: roundMoney(snapshotSource.storeDeliveryFeeAmount),
      appReceivableAmount: roundMoney(snapshotSource.appReceivableAmount),
      storeNetAmount: roundMoney(snapshotSource.storeNetAmount),
      subtotal: roundMoney(snapshotSource.subtotal ?? order?.subtotal),
      deliveryFee: roundMoney(snapshotSource.deliveryFee ?? order?.delivery_fee),
    };
  }

  const subtotal = roundMoney(order?.subtotal);
  const explicitServiceFee = roundMoney(order?.service_fee);
  const explicitDeliveryFee = roundMoney(order?.delivery_fee);
  const commissionAmount = resolveCommissionAmount(subtotal, profile);
  const serviceFeeAmount = resolveServiceFeeAmount(subtotal, explicitServiceFee, profile);
  const delivery = resolveDeliveryBreakdown({
    order,
    profile,
    explicitDeliveryFee,
    subtotal,
  });
  const appReceivableAmount = roundMoney(
    commissionAmount + serviceFeeAmount + delivery.appDeliveryFeeAmount
  );
  const storeNetAmount = roundMoney(
    subtotal -
      commissionAmount -
      serviceFeeAmount -
      delivery.appDeliveryFeeAmount +
      delivery.storeDeliveryFeeAmount
  );
  const issuedAt =
    order?.customer_confirmed_at ||
    order?.completed_at ||
    order?.delivered_at ||
    order?.updated_at ||
    order?.created_at ||
    new Date().toISOString();

  return {
    subtotal,
    deliveryFee: delivery.deliveryFee,
    courierSource: delivery.courierSource,
    deliveryType: delivery.deliveryType,
    commissionType: profile.commissionType,
    commissionValue: profile.commissionValue,
    commissionAmount,
    serviceFeeType: profile.serviceFeeType,
    serviceFeeValue: profile.serviceFeeValue,
    serviceFeeAmount,
    deliveryFeeMode: profile.deliveryFeeMode,
    appDeliveryFeeValue: profile.appDeliveryFeeValue,
    storeDeliveryFeeValue: profile.storeDeliveryFeeValue,
    appDeliveryFeeAmount: delivery.appDeliveryFeeAmount,
    storeDeliveryFeeAmount: delivery.storeDeliveryFeeAmount,
    appReceivableAmount,
    storeNetAmount,
    settlementCycle: profile.settlementCycle,
    distributionPolicy: profile.distributionPolicy,
    gracePeriodDays: profile.gracePeriodDays,
    profileVersion: profile.profileVersion,
    effectiveFrom: profile.effectiveFrom,
    issuedAt,
  };
}

export function parseStoredFinancialSnapshot(value) {
  const normalized = normalizeJsonObject(value);
  if (!normalized) return null;
  return computeOrderFinancialSnapshot({
    subtotal: normalized.subtotal,
    service_fee: normalized.serviceFeeAmount,
    delivery_fee: normalized.deliveryFee,
    financial_config_snapshot_json: normalized,
  });
}

export { roundMoney, toNumber };
